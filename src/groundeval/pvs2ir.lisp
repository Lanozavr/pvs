;;pvs2ir translates PVS expressions, definitions, and theories to an intermediate
;;representation (IR).  The IR consists of variables, tuples, function applications,
;;lambda-expressions, if-expressions, lets, and updates.

(defcl ir-expr ()
  (ir-freevars :initform 'unbound :fetch-as 'unbound))

(defcl ir-type ())

(defcl ir-integer (ir-expr)
  ir-intval)

(defcl ir-bool (ir-expr)
  ir-boolval)

(defcl ir-variable (ir-expr)
  ir-name
  ir-vtype)

(defcl ir-apply (ir-expr)
  ir-func
  ir-args)

(defcl ir-let (ir-expr)
  ir-vartype ;an ir-variable
  ir-bind-expr
  ir-body)

(defcl ir-record (ir-expr)
  ir-fields
  ir-recordtype)

(defcl ir-field (ir-expr)
  ir-fieldname
  ir-value)

(defcl ir-lambda (ir-expr)
  ir-vartypes ; list of ir-types
  ir-rangetype
  ir-body)

(defcl ir-ift (ir-expr)
  ir-condition
  ir-then
  ir-else)

(defcl ir-switch (ir-expr)
  ir-cvar
  ir-selections
  ir-switch-else)

(defcl ir-selection (ir-expr)
  ir-svalue ir-sbranch)

(defcl ir-nil (ir-expr))

(defcl ir-lookup (ir-expr);;not used
  ir-array
  ir-index)

(defcl ir-update (ir-expr)
  ir-target
  ir-lhs
  ir-rhs)

(defcl ir-constructor-update (ir-update))  ;;this is for the internal update operation to preserve refcounts

(defcl ir-new (ir-expr)
  ir-size
  ir-etype)

(defcl ir-get (ir-expr)
  ir-record
  ir-field)

(defcl ir-typename (ir-type)
  ir-type-id
  ir-type-defn)

(defcl ir-recordtype (ir-type)
  ir-field-types)

(defcl ir-adt-recordtype (ir-recordtype)
  ir-field-types
  ir-constructors)

(defcl ir-adt-constructor-recordtype (ir-recordtype)
  ir-field-types
  ir-adt-name)

(defcl ir-fieldtype (ir-type)
  ir-id ir-ftype)

(defcl ir-funtype (ir-type)
  ir-domain
  ir-range)

(defcl ir-subrange (ir-type)
  ir-low ir-high)

;;NSH(1/27/16): These classes are not being used. 
;;An ADT is a name (id) and a list of constructors.  Each constructor has a name
;;and a list of accessors, and each accessor has a name and type.  
(defcl ir-adt-constructor ()
  ir-adt-constructor-id
  ir-adt-constructor-index
  ir-adt-accessors)

(defcl ir-adt-accessor ()
  ir-adt-accessor-id
  ir-adt-accessor-type)

(defcl ir-adt (ir-type)
  ir-adt-name
  ir-adt-constructors)


;;other types are char, bool, int32_t, int64_t, uint32_t, uint64_t, mpi, and mpz
;;we'll add floats later on.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;From Sam:
;;; Generates a unique id for a given typechecked decl
;;; Currently assumes the decl id is unique except for const-decls
;;; If the const-decl is unique already, simply returns it.
;;; Otherwise creates, e.g., the symbol 'c_2' for the second decl
;;; with id 'c' in the list of all declarations for the theory
;;; the decl occurs in.
;;;It's modified here to remove non-ascii symbols and to replace ? with p
;;;so as to avoid duplicates.
(defun simple-id (id)
  (intern (substitute #\p #\? (string (op-to-id id)))))

(defun pvs2ir-unique-decl-id (decl)
  (let ((module-id (simple-id (id (module decl))))
	(decl-id (simple-id (id decl))))
  (if (const-decl? decl)
      (let ((same-id-decls (remove-if
			       (complement #'(lambda (d)
					       (and (const-decl? d)
						    (eq (simple-id (id d)) decl-id))))
			     (all-decls (module decl)))))
	(assert (memq decl same-id-decls))
	(if (cdr same-id-decls)
	    (let ((idx (1+ (position decl same-id-decls))))
	      (intern (format nil "~a_~a_~d" module-id decl-id idx) :pvs))
	  (intern (format nil "~a_~a" module-id decl-id))))
    (intern (format nil "~a_~a" module-id decl-id)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defparameter *ir-primitives*
  '(= /= TRUE FALSE IMPLIES => <=> AND & OR NOT WHEN IFF + - * /
   number_field_pred < <= > >= real_pred integer_pred integer?
   rational_pred floor ceiling rem ndiv even? odd? cons car cdr cons?
   null null? restrict length member nth append reverse))

(defparameter *ir-arith-primitives*
  '(+ - * / number_field_pred = < <= > >= real_pred integer_pred integer?
   rational_pred floor ceiling rem ndiv even? odd? AND OR IMPLIES WHEN))

(defvar *var-counter* nil)
(defmacro new-irvar () ;;index this by the theory and declaration so that labels are stable
  `(intern (format nil "ivar_~a"  (funcall *var-counter*))))

(defvar *ir-type-def-hash* (make-hash-table :test #'eq))

(defmacro new-irvars (length)
  `(loop for index from 1 to ,length collect (new-irvar)))

;;this revises the definition in classes-decl.lisp and should replace it. 
(defcl eval-info ()
  ir
  cdefn
  internal  ;both are eval-defn-info 
  external)

(defcl eval-type-info ()
  ir-type-name)


(defun mk-eval-type-info (name)
  (make-instance 'eval-type-info
		 :ir-type-name name))


(defcl constructor-eval-info (eval-info)
  ctype)

(defcl accessor-eval-info (eval-info)
  update-cdefn)

(defcl type-decl (declaration)
  (type-value :store-as ignore-self-reference-type-values)
  (ir-type-value))

(defcl ir-defn ()
  ir-function-name
  ir-defn)

(defcl ir-constructor-defn (ir-defn)
  ir-constructor-type)

(defcl ir-accessor-defn (ir-defn)
  ir-update-defn) ;this slot is itself an ir-defn

(defun mk-ir-variable (ir-name ir-type)
  (make-instance 'ir-variable
		 :ir-name ir-name
		 :ir-vtype ir-type))

(defun mk-ir-integer (intval)
  (make-instance 'ir-integer
		 :ir-intval intval))

(defun mk-ir-bool (bval)
  (make-instance 'ir-bool
		 :ir-boolval bval))

(defun mk-ir-nil ()
  (make-instance 'ir-nil))

(defun mk-ir-new (size etype)
  (make-instance 'ir-new
		 :ir-size size
		 :ir-etype etype))

(defun mk-ir-apply (function args)
  (make-instance 'ir-apply
		 :ir-func function
		 :ir-args args))

(defun mk-ir-let (vartype expr body)
  (make-instance 'ir-let
		 :ir-vartype vartype
		 :ir-bind-expr expr
		 :ir-body body))

(defun mk-ir-record (fields type)
  (make-instance 'ir-record
		 :ir-fields fields
		 :ir-recordtype type))

(defun mk-ir-field (fieldname value)
  (make-instance 'ir-field
		 :ir-fieldname fieldname
		 :ir-value value))

(defun mk-ir-update (target lhs rhs)
  (make-instance 'ir-update
		 :ir-target target
		 :ir-lhs lhs
		 :ir-rhs rhs))

(defun mk-ir-constructor-update (target lhs rhs)
  (make-instance 'ir-constructor-update
		 :ir-target target
		 :ir-lhs lhs
		 :ir-rhs rhs))

(defun mk-ir-lambda (vartypes rangetype body)
  (make-instance 'ir-lambda
		 :ir-vartypes vartypes
		 :ir-rangetype rangetype
		 :ir-body  body))

(defun mk-ir-ift (condition then else)
  (make-instance 'ir-ift
		 :ir-condition condition
		 :ir-then then
		 :ir-else else))

(defun mk-ir-selection (svalue sbranch)
  (make-instance 'if-selection :ir-svalue svalue :ir-sbranch sbranch))

(defun mk-ir-switch (cvar selections else)
  (make-instance 'ir-switch
		 :ir-cvar cvar
		 :ir-selections selections
		 :ir-switch-else else))

(defun mk-ir-lookup (array index)
  (make-instance 'ir-lookup
		 :ir-array array
		 :ir-index index))

(defun mk-ir-get (record field)
  (make-instance 'ir-get
		 :ir-record record
		 :ir-field field))

(defun mk-ir-typename (id defn)
  (make-instance 'ir-typename
		 :ir-type-id id
		 :ir-type-defn defn))

(defun mk-ir-recordtype (field-types)
  (make-instance 'ir-recordtype
		 :ir-field-types field-types))

(defun mk-ir-adt-recordtype (field-types constructors)
  (make-instance 'ir-adt-recordtype
		 :ir-field-types field-types
		 :ir-constructors constructors))

(defun mk-ir-adt-constructor-recordtype (field-types adt-name)
  (make-instance 'ir-adt-constructor-recordtype
		 :ir-field-types field-types
		 :ir-adt-name adt-name))



(defun mk-ir-fieldtype (id type)
  (make-instance 'ir-fieldtype
		 :ir-id id
		 :ir-ftype type))

(defun mk-ir-funtype (domain range)
  (make-instance 'ir-funtype
		 :ir-domain domain
		 :ir-range range))

(defun mk-ir-subrange (low high)
  (make-instance 'ir-subrange
		 :ir-low low
		 :ir-high high))

(defun mk-ir-adt-constructor (id index accessors)
  (make-instance 'ir-adt-constructor
		 :ir-adt-constructor-id id
		 :ir-adt-constructor-index index
		 :ir-adt-accessors accessors))

(defun mk-ir-adt-accessor (id type)
  (make-instance 'ir-adt-accessor
		 :ir-adt-accessor-id id
		 :ir-adt-accessor-type type))

(defun mk-ir-adt (id constructors)
  (make-instance 'ir-adt
		 :ir-adt-name id
		 :ir-adt-constructors constructors))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun decl-context (decl &optional include?)
  (let* ((*generate-tccs* 'none)
	 (theory (module decl))
	 (libalist (when *current-context*
		     (library-alist *current-context*))) ;; Before we change
	 (all-decls (reverse (all-decls theory)))
	 (pdecls (or (memq decl all-decls) (cons decl all-decls)))
	 (prev-decls (if include?
			 pdecls
			 (cdr pdecls)))
	 (prev-imp (find-if #'mod-or-using? prev-decls))
	 (rem-decls (if (and prev-imp (saved-context prev-imp))
			(ldiff prev-decls (memq prev-imp prev-decls))
			prev-decls))
	 (*current-theory* theory)
	 (*current-context*
	  (cond ((and prev-imp (saved-context prev-imp))
		 (copy-context (saved-context prev-imp)
			       theory (reverse rem-decls)
			       (or (car rem-decls) decl)))
		((from-prelude? decl)
		 (let ((prevp
			(cadr (memq theory
				    (reverse
				     *prelude-theories*)))))
		   (if prevp
		       (copy-context (saved-context
				      (if (datatype? prevp)
					  (or (adt-reduce-theory prevp)
					      (adt-map-theory prevp)
					      (adt-theory prevp))
					  prevp))
				     theory
				     (reverse rem-decls)
				     (or (car rem-decls) decl))
		       (copy-context (saved-context theory)))))
		(t (make-new-context theory)))))
    ;;; Need to clear this hash or the known-subtypes table won't get
    ;;; updated properly - see add-to-known-subtypes.
    (clrhash *subtype-of-hash*)
    (with-current-decl decl
      (dolist (d (reverse rem-decls))
	(typecase d
	  (lib-decl
	   (check-for-importing-conflicts d)
	   (put-decl d))
	  ((or mod-decl theory-abbreviation-decl formal-theory-decl)
	   (put-decl d)
	   (let* ((thname (theory-name d))
		  (th (get-theory thname)))
	     (add-usings-to-context* th thname))
	   (setf (saved-context d) (copy-context *current-context*)))
	  (importing
	   (let* ((thname (theory-name d))
		  (th (get-theory* (id thname)
				   (or (library thname)
				       (and (library-datatype-or-theory? theory)
					    (car (rassoc (lib-ref theory) libalist
							 :test #'string=)))))))
	     (assert th)
	     (add-usings-to-context* th thname))
	   (setf (saved-context d) (copy-context *current-context*)))
	  ;;(subtype-judgement (add-to-known-subtypes (subtype d) (type d)))
	  (judgement (add-judgement-decl d t))
	  (conversionminus-decl (disable-conversion d))
	  (conversion-decl (push d (conversions *current-context*)))
	  (auto-rewrite-minus-decl (push d (disabled-auto-rewrites
					    *current-context*)))
	  (auto-rewrite-decl (add-auto-rewrite-to-context  d))
	  (type-def-decl (unless (enumtype? (type-expr d))
			   (put-decl d)))
	  (declaration (put-decl d))
	  (datatype nil)))
      (when (from-prelude? decl)
	(let* ((prevp (cadr (memq theory
				  (reverse *prelude-theories*))))
	       (pths (if (datatype? prevp)
			 (delete-if #'null
			   (list (adt-theory prevp)
				 (adt-map-theory prevp)
				 (adt-reduce-theory prevp)))
			 (if prevp
			     (list prevp)
			     (list theory)))))
	  (dolist (pth pths)
	    (setf (get-importings pth)
		  (list (mk-modname (id pth)))))))
      (update-context-importing-for-mapped-tcc decl))
    (setf (declaration *current-context*) decl)
    *current-context*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defmethod print-ir ((ir-expr ir-integer))
  (with-slots (ir-intval) ir-expr
	      ir-intval))

(defmethod print-ir ((ir-expr ir-bool))
  (with-slots (ir-boolval) ir-expr
	      (if ir-boolval 'true 'false)))

(defmethod print-ir ((ir-expr ir-variable))
  `(,(ir-name ir-expr) ,(print-ir (ir-vtype ir-expr))))

(defmethod print-ir ((ir-expr ir-apply))
  (with-slots (ir-func ir-args) ir-expr
	      `(,(print-ir ir-func) ,@(print-ir ir-args))))

(defmethod print-ir ((ir-expr ir-let))
  (with-slots (ir-vartype ir-bind-expr ir-body) ir-expr
	      (with-slots (ir-name ir-vtype) ir-vartype
			  `(let ,ir-name ,(print-ir ir-vtype)
				,(print-ir ir-bind-expr)
				,(print-ir ir-body)))))

(defmethod print-ir ((ir-expr ir-record ))
  (with-slots (ir-fields) ir-expr
	      `(record ,(print-ir ir-fields))))

(defmethod print-ir ((ir-expr ir-field))
  (with-slots (ir-fieldname ir-value) ir-expr
	      `(= ,ir-fieldname ,(print-ir ir-value))))

(defmethod print-ir ((ir-expr ir-lambda))
  (with-slots (ir-vartypes ir-rangetype ir-body) ir-expr
  `(lambda (,@(print-ir ir-vartypes)) '-> ,(print-ir ir-rangetype) ,(print-ir ir-body))))

(defmethod print-ir ((ir-expr ir-ift))
  (with-slots (ir-condition ir-then ir-else) ir-expr
	      `(if ,(print-ir ir-condition) ,(print-ir ir-then) ,(print-ir ir-else))))

(defmethod print-ir ((ir-expr ir-nil))
  nil)

(defmethod print-ir ((ir-expr ir-lookup))
  (with-slots (ir-array ir-index) ir-expr
	      `(lookup ,(print-ir ir-array) ,(print-ir ir-index))))

(defmethod print-ir ((ir-expr ir-update))
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      `(update ,(print-ir ir-target) ,(print-ir ir-lhs) ,(print-ir ir-rhs))))

(defmethod print-ir ((ir-expr ir-constructor-update))
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      `(update-constructor ,(print-ir ir-target) ,(print-ir ir-lhs) ,(print-ir ir-rhs))))

(defmethod print-ir ((ir-expr ir-new))
  (with-slots (ir-size ir-etype) ir-expr
	      `(new ,ir-size ,(print-ir ir-etype))))

(defmethod print-ir ((ir-expr ir-get))
  (with-slots (ir-record ir-field) ir-expr
	      `(get ,(print-ir ir-record) ,ir-field)))

(defmethod print-ir ((ir-type ir-typename))
  (with-slots (ir-type-id ir-type-defn) ir-type
	      ir-type-id))

(defmethod print-ir ((ir-type ir-recordtype))
  (with-slots (ir-field-types) ir-type
	      `(recordtype ,(print-ir ir-field-types))))

(defmethod print-ir ((ir-type ir-adt-recordtype))
  (with-slots (ir-field-types ir-constructors) ir-type
	      `(adt-recordtype ,(print-ir ir-field-types) :constructors ir-constructors)))

(defmethod print-ir ((ir-type ir-adt-constructor-recordtype))
  (with-slots (ir-field-types ir-adt-name) ir-type
	      `(constructor-recordtype ,(print-ir ir-field-types) :adt ir-adt-name)))

(defmethod print-ir ((ir-type ir-fieldtype))
  (with-slots (ir-id ir-ftype) ir-type 
	      `(=> ,ir-id ,(print-ir ir-ftype))))

(defmethod print-ir ((ir-type ir-funtype))
  (with-slots (ir-domain ir-range) ir-type
	      `(-> ,(print-ir ir-domain) ,(print-ir ir-range))))

(defmethod print-ir ((ir-type ir-subrange))
  (with-slots (ir-low ir-high) ir-type
	      `(subrange ,ir-low ,ir-high)))

(defmethod print-ir ((ir-expr list))
  (cond ((consp ir-expr)
	 (cons (print-ir (car ir-expr))
	       (print-ir (cdr ir-expr))))
	(t nil)))

(defmethod print-ir ((ir-expr t))
  ir-expr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun pvs2ir (expr &optional context)
    (let* ((*var-counter* nil)
	   (*current-context*
	    (if context context *current-context*))
	   (*current-theory* (theory *current-context*))
	   (*generate-tccs* 'none))
      (newcounter *var-counter*)
      (pvs2ir* expr nil)))

(defmethod pvs2ir* ((expr number-expr) bindings)
  (declare (ignore bindings))
  (with-slots (number) expr
	      (mk-ir-integer number)))

(defmethod pvs2ir* ((expr name-expr) bindings)
    (let* ((decl (declaration expr))
	   (bnd (assoc  decl bindings :key #'declaration)))
      (assert (not (and bnd (const-decl? decl))))
      (if bnd
	  (cdr bnd)
	(if (const-decl? decl)
	    (let* ((expr-actuals (expr-actuals (module-instance expr)))
		   (ir-actuals (when expr-actuals
				 (pvs2ir* expr-actuals ;;needs to be fixed when handling actuals
					bindings)))
		   (ir-vars (new-irvars (length ir-actuals)))
		   (actuals-types (mapcar #'type expr-actuals))

		   (ir-actuals-types (mapcar #'pvs2ir-type actuals-types))
		   (ir-vartypes (loop for ir-var in ir-vars
				      as ir-act in ir-actuals-types
				      collect (mk-ir-variable ir-var ir-act)))
		   (ir-function (pvs2ir-constant expr)))
	      (if ir-actuals
		  (mk-ir-let* ir-vartypes ir-actuals
			      (mk-ir-apply ir-function ir-vars))
		ir-function))
	  (break "Should not happen")))))

(defmethod pvs2ir* ((expr lambda-expr) bindings)
  (with-slots ((expr-bindings bindings) expression) expr 
	      (let* ((binding-vars (new-irvars (length expr-bindings)))
		     (ir-binds (loop for irvar in binding-vars
				  as bind in expr-bindings
				  collect (mk-ir-variable irvar (pvs2ir-type (type bind)))))
		     (ir-var-bindings (pairlis expr-bindings ir-binds))
		     (ir-rangetype (pvs2ir-type (type expression)))
		     (ir-expr (pvs2ir* expression (append ir-var-bindings bindings))));(break "lambda")
		(mk-ir-lambda ir-binds ir-rangetype ir-expr))))

(defmethod pvs2ir* ((expr application) bindings)
  (with-slots (operator argument) expr
	      (pvs2ir-application operator (arguments expr) bindings)))


(defun mk-ir-let* (vartypes exprs body)
  (cond ((consp vartypes)
	 (mk-ir-let (car vartypes)(car exprs)
		    (mk-ir-let* (cdr vartypes)(cdr exprs) body)))
	(t body)))

(defun adt-decl? (decl)
  (or (adt-constructor-decl? decl)
      (adt-accessor-decl? decl)
      (adt-recognizer-decl? decl)))

(defun pvs2ir-decl (decl)
  (let* ((*current-context* (decl-context decl))
	 (*current-theory* (theory *current-context*))
	 (*generate-tccs* 'none))
    (pvs2ir-decl* decl)))

(defun copy-without-print-type (type)
  (copy type 'print-type nil))

(defmethod pvs2ir-decl* ((decl type-eq-decl))
  (let ((ir-type-value (ir-type-value decl)))
    (if ir-type-value
	(ir-type-name ir-type-value)
      (let* ((ir-type (pvs2ir-type (copy-without-print-type (type-value decl))))
	     (ir-type-id (pvs2ir-unique-decl-id decl))
	     (ir-type-name (mk-ir-typename ir-type-id ir-type)))
	(push ir-type-name *ir-type-info-table*)
	(setf (ir-type-value decl)
	      (mk-eval-type-info ir-type-name))
	(ir-type-name (ir-type-value decl))))))

(defmethod pvs2ir-decl* ((decl type-decl))
  (and (or (ir-type-value decl)
	   (let ((type-value (type-value decl)))
	     (and type-value
		  (adt type-value)
		  (pvs2ir-adt-decl decl))))
       (ir-type-name (ir-type-value decl))))

(defmethod pvs2ir-decl* ((decl const-decl))
  (let* ((einfo (eval-info decl))
	 (einfo (or einfo
		    (let ((new-einfo (make-instance 'eval-info)))
		      (setf (eval-info decl) new-einfo)
		      new-einfo))))
    (let* ((ir-einfo (ir einfo))
	   (ir-function-name (when ir-einfo (ir-function-name ir-einfo))))
      (or ir-function-name
	  (let* ((defns (def-axiom decl))
		 (defn (when defns (args2 (car (last (def-axiom decl)))))))
	    (unless ir-einfo ;first create eval-info then fill the function name
		  (setf (ir einfo)
			(make-instance 'ir-defn)))
	    (setf (ir-function-name (ir einfo))
		  (intern (format nil "f_~a" (pvs2ir-unique-decl-id decl))))
		;;create the ir for the definition
	    (let* ((context (decl-context decl))
;		   (*current-theory* (theory context))
		   (ir-defn (pvs2ir defn context)))
	      (setf (ir-defn (ir einfo)) ir-defn)
	      (ir-function-name (ir einfo))))))))

(defun pvs2ir-constant (expr)
  (let ((decl (declaration expr)))
    (cond ((pvs2cl-primitive? expr) ;;borrowed from pvseval-update.lisp
	   (id expr))
	  (t 
	   (if (adt-decl? decl)
	       (let ((adt (adt expr)))
		 (pvs2ir-adt adt)
		 (ir-function-name (ir (eval-info decl))))
	     (pvs2ir-decl decl))))))

(defun pvs2ir-adt (adt)
  (let* ((adt-decl (declaration adt)));(break "adt")
	(pvs2ir-adt-decl adt-decl)))

(defun pvs2ir-adt-decl (adt-decl);;only called with ir-type-value is empty
  (let* ((adt-type (type-value adt-decl))
	 (adt-type-id (pvs2ir-unique-decl-id adt-decl))
	 (adt (adt adt-type))
	 (constructors (constructors adt))
	 (index-id (intern (format nil "~a_index" adt-type-id)))
	 (index-type (mk-ir-subrange 0 (1- (length constructors))))
	 (adt-recordtype (mk-ir-adt-recordtype (list (mk-ir-fieldtype index-id
								      index-type))
					       (loop for con in constructors
						     collect (cons (pvs2ir-unique-decl-id (con-decl con))
								   (loop for acc in (acc-decls con)
									 collect (pvs2ir-unique-decl-id acc))))))
	 (adt-type-name (mk-ir-typename adt-type-id adt-recordtype)))
    (push adt-type-name *ir-type-info-table*)
    (setf (ir-type-value adt-decl)
	  (mk-eval-type-info adt-type-name))
    (loop for constructor in constructors
	  as index from 0
	  do (pvs2ir-adt-constructor constructor index index-id index-type adt-recordtype adt-type-name))
    ;(break "before accessor")
    (loop for constructor in constructors
	  as index from 0
	  do (pvs2ir-adt-accessors (acc-decls constructor) constructor constructors
				   index index-id 
				   adt-type-name))
    adt-type-name
    ))

	 
(defun pvs2ir-adt-constructor (constructor index index-id index-type adt-recordtype adt-type-name)
  (let* ((cdecl (con-decl constructor))
	 (args (arguments constructor))
	 (cid (pvs2ir-unique-decl-id cdecl))
	 (einfo (get-eval-info cdecl))
	 (*var-counter* nil))
    (newcounter *var-counter*)
    (unless (ir einfo);(break "constructor")
      (setf (ir einfo) (make-instance 'ir-constructor-defn))
      (let* ((indexvar (mk-ir-variable (new-irvar) index-type))
	     (cargs (loop for arg in args
			  collect (mk-ir-variable (new-irvar);;range is the same for shared accessors
						  (pvs2ir-type (declared-type arg)))))
	     (cbody-fields (cons (mk-ir-field index-id indexvar)
				 (loop for arg in args
				       as carg in cargs
				       collect (mk-ir-field (id arg) carg))))
	     (accessor-types (loop for arg in args
					      as carg in cargs 
					      collect (mk-ir-fieldtype (id arg)
								       (ir-vtype carg))))
	     (cbody-field-types (append (ir-field-types adt-recordtype);;add the index field
					accessor-types))
	     (cbody-recordtype (mk-ir-adt-constructor-recordtype cbody-field-types adt-type-name))
	     (ctypename (mk-ir-typename cid cbody-recordtype))
	     (cvar (mk-ir-variable (new-irvar) ctypename))
	     (cbody-record (mk-ir-record cbody-fields cbody-recordtype))
	     (cbody (mk-ir-let indexvar (mk-ir-integer index)
			       (mk-ir-let cvar cbody-record cvar))));(break "c2")
	(setf (ir-constructor-type (ir einfo)) ctypename);(break "-constructor")
	(setf (ir-function-name (ir einfo))
	      cid
	      (ir-defn (ir einfo))
	      (if cargs (mk-ir-lambda cargs adt-type-name cbody)
		cbody)) ;;for 0-ary constructors
	(pvs2ir-adt-recognizer (rec-decl constructor) index index-id index-type adt-type-name)
	))))

(defun pvs2ir-adt-accessors (acc-decls constructor constructors
				       index index-id 
				       adt-type-name)
  (cond ((consp acc-decls)
	 (and (pvs2ir-adt-accessor* (car acc-decls) constructor constructors
				   index index-id adt-type-name)
	      (pvs2ir-adt-accessors (cdr acc-decls) constructor constructors
				   index index-id adt-type-name)))
	(t nil)))

(defun get-eval-info (declaration)
  (or (eval-info declaration)
      (let ((new-einfo (if (adt-constructor-decl? declaration)
			   (make-instance 'constructor-eval-info)
			 (if (adt-accessor-decl? declaration)
			     (make-instance 'accessor-eval-info)
			   (make-instance 'eval-info)))))
	(setf (eval-info declaration) new-einfo)
	new-einfo)))

(defun pvs2ir-adt-recognizer (rdecl index index-id index-type adt-type-name)
  (let* ((einfo (get-eval-info rdecl))
	 (ir-einfo (ir einfo))
	 (*var-counter* nil))
    (newcounter *var-counter*)
    (or ir-einfo
	(let* ((rid (pvs2ir-unique-decl-id rdecl))
	       (rargs (list (mk-ir-variable (new-irvar) adt-type-name)))
	       (index-expr (mk-ir-get (car rargs) index-id))
	       (index-expr-var (mk-ir-variable (new-irvar) index-type))
	       (index-var (mk-ir-variable (new-irvar) index-type))
	       (check-expr (mk-ir-apply '= (list index-expr-var index-var)))
	       (rbody (mk-ir-let index-var (mk-ir-integer index)
				 (mk-ir-let index-expr-var index-expr
					    check-expr)))
	       (rdefn (mk-ir-lambda rargs 'bool rbody)));(break "recognizer")
	  (setf (ir einfo)(make-instance 'ir-defn))
	  (setf (ir-function-name (ir einfo))
		(intern (format nil "r_~a" rid))
		(ir-defn (ir einfo))
		rdefn)))))


(defmethod pvs2ir-adt-accessor* ((adecl adt-accessor-decl)
				 constructor constructors index index-id adt-type-name)
   (let* ((adecl-id (id adecl))
	 (einfo (get-eval-info adecl))
	 (ir-einfo (ir einfo))
	 (cinfo (get-eval-info (con-decl constructor)))
	 (ir-cinfo (ir cinfo))
	 (ctype (ir-constructor-type ir-cinfo))
	 (*var-counter* nil))
    (newcounter *var-counter*)
    (or (ir einfo)
	(let* ((aid (pvs2ir-unique-decl-id adecl))
	       (aargvar (mk-ir-variable (new-irvar) adt-type-name))
	       (accessor-ir-type (pvs2ir-type (range (type adecl))))
	       (cast-var (mk-ir-variable (new-irvar) ctype))
	       (project-expr (mk-ir-get cast-var adecl-id))
	       (abody (mk-ir-let cast-var aargvar
				 project-expr))
	       (adefn (mk-ir-lambda (list aargvar) accessor-ir-type abody))
	       (new-value-var (mk-ir-variable (new-irvar) accessor-ir-type))
	       (ubody (mk-ir-let cast-var aargvar (mk-ir-constructor-update cast-var adecl-id new-value-var))))
	  (setf (ir einfo)(make-instance 'ir-accessor-defn)
		(ir-update-defn (ir einfo)) (make-instance 'ir-defn))
	  (format t "~%Adding definition for singular accessor: ~a" adecl-id)
	  (setf (ir-function-name (ir einfo))
		(format nil "~a_~a" (ir-type-id adt-type-name) adecl-id)
		(ir-defn (ir einfo))
		adefn
		(ir-function-name (ir-update-defn (ir einfo)))
		(format nil "update_~a_~a" (ir-type-id adt-type-name) adecl-id)
		(ir-defn (ir-update-defn (ir einfo)))
		(mk-ir-lambda (list aargvar new-value-var) ctype ubody)
		)))))

(defmethod pvs2ir-adt-accessor* ((adecl shared-adt-accessor-decl)
				 constructor constructors index index-id adt-type-name)
  (let* ((adecl-id (id adecl))
	 (einfo (get-eval-info adecl))
	 (ir-einfo (ir einfo))
	 (*var-counter* nil))
    (newcounter *var-counter*)
    (or ir-einfo
	(let* ((acc-constructor-ids (constructors adecl))
	       (acc-constructor-index-decls (loop for cnstr in constructors
						  as idx from 0 
						  when (memq (id cnstr) acc-constructor-ids)
						  collect (cons idx (con-decl cnstr))))
	       (aid (pvs2ir-unique-decl-id adecl))
	       (aargvar (mk-ir-variable (new-irvar) adt-type-name))
	       (accessor-ir-type (pvs2ir-type (range (type adecl))))
	       (abody (pvs2ir-accessor-body adecl-id aargvar acc-constructor-index-decls index-id))
	       (new-value-var (mk-ir-variable (new-irvar) accessor-ir-type))
	       (ubody (pvs2ir-accessor-update-body adecl-id aargvar new-value-var
						   acc-constructor-index-decls index-id)))
	  (setf (ir einfo)(make-instance 'ir-accessor-defn)
		(ir-update-defn (ir einfo)) (make-instance 'ir-defn))
	  (format t "~%Adding definition for shared accessor: ~a" adecl-id)
	  (setf (ir-function-name (ir einfo))
		(format nil "~a_~a" (ir-type-id adt-type-name) adecl-id)
		(ir-defn (ir einfo))
		(mk-ir-lambda (list aargvar) accessor-ir-type abody)
		(ir-function-name (ir-update-defn (ir einfo)))
		(format nil "update_~a_~a" (ir-type-id adt-type-name) adecl-id)
		(ir-defn (ir-update-defn (ir einfo))) ;no unique constructor so return type below is adt-type-name
		(mk-ir-lambda (list aargvar new-value-var) adt-type-name ubody))))))
	       
	 ;; (ctypes (map #'id acc-constructors))
	 ;; (cinfo (get-eval-info (declaration constructor)))
	 ;; (ir-cinfo (ir cinfo))
	 ;; (ctype (ir-function-name ir-cinfo)))))))

;;pvs2ir-accessor-body builds the body of a multi-constructor accessor for the given accessor
(defun pvs2ir-accessor-body (adecl-id aargvar acc-constructor-index-decls index-id)
  (break "pvs2ir-accessor-body")
    (cond ((consp  acc-constructor-index-decls)
	   (let* ((cindex (caar acc-constructor-index-decls))
		  (cdecl (cdar acc-constructor-index-decls))
		  (cbranch (let ((cast-var (mk-ir-variable (new-irvar)
							   (ir-constructor-type (ir (get-eval-info cdecl))))))
			     (mk-ir-let cast-var  aargvar (mk-ir-get  cast-var adecl-id)))));(break "acc-body")
	     (if (consp (cdr acc-constructor-index-decls))
		 (let ((condvar (mk-ir-variable (new-irvar) 'bool))
		       (indvar (mk-ir-variable (new-irvar) 'uint32))
		       (intvar (mk-ir-variable (new-irvar) 'uint32)))
		   (mk-ir-let condvar
			      (mk-ir-let indvar
					 (mk-ir-get aargvar index-id)
					 (mk-ir-let intvar (mk-ir-integer cindex)
						    (mk-ir-apply '= (list indvar intvar))))
			      (mk-ir-ift condvar
					 cbranch
					 (pvs2ir-accessor-body adecl-id aargvar (cdr acc-constructor-index-decls) index-id))))
	       cbranch)))
	  (t (format t "Shouldn't reach here."))))

;;pvs2ir-accessor-update-body builds the body of a multi-constructor update for the given accessor
(defun pvs2ir-accessor-update-body (adecl-id aargvar new-value-var
					     acc-constructor-index-decls index-id)
    (cond ((consp  acc-constructor-index-decls)
	   (let* ((cindex (caar acc-constructor-index-decls))
		  (cdecl (cdar acc-constructor-index-decls))
		  (cbranch (let ((cast-var (mk-ir-variable (new-irvar)
							   (ir-constructor-type (ir (get-eval-info cdecl))))))
			     (mk-ir-let cast-var  aargvar
					(mk-ir-constructor-update cast-var adecl-id new-value-var)))));(break "acc-body")
	     (if (consp (cdr acc-constructor-index-decls))
		 (let ((condvar (mk-ir-variable (new-irvar) 'bool))
		       (indvar (mk-ir-variable (new-irvar) 'uint32))
		       (intvar (mk-ir-variable (new-irvar) 'uint32)))
		   (mk-ir-let condvar
			      (mk-ir-let indvar
					 (mk-ir-get aargvar index-id)
					 (mk-ir-let intvar (mk-ir-integer cindex)
						    (mk-ir-apply '= (list indvar intvar))))
			      (mk-ir-ift condvar
					 cbranch
					 (pvs2ir-accessor-update-body adecl-id aargvar new-value-var (cdr acc-constructor-index-decls) index-id))))
	       cbranch)))
	  (t (format t "Shouldn't reach here."))))

(defmethod pvs2ir-constructor-recordtype ((constructor ir-adt-constructor))
  (let ((index-fieldtype (mk-ir-fieldtype (intern "_index")
					  (mk-ir-subrange (ir-adt-constructor-index constructor)
							  (ir-adt-constructor-index constructor))))
	(rest-fieldtypes (loop for accessor in (ir-adt-accessors constructor)
			       collect (mk-ir-fieldtype (ir-adt-accessor-id accessor)
							 (ir-adt-accessor-type accessor)))))
    (mk-ir-recordtype (cons index-fieldtype rest-fieldtypes))))


(defun pvs2ir-application (op args bindings)
  (let* ((arg-names (new-irvars (length args)))
	 (arg-types (if (pvs2cl-primitive? op)
			(loop for arg in args 
			  collect (pvs2ir-type (type arg)))
			(loop for type in (types (domain (type op)))
			  collect (pvs2ir-type type))))
	 (arg-vartypes (loop for ir-var in arg-names
			     as ir-typ in arg-types
			     collect (mk-ir-variable ir-var ir-typ)))
	 (args-ir (pvs2ir* args bindings)))
    (if (constant? op)
	(mk-ir-let* arg-vartypes
		    args-ir
		    (mk-ir-apply (pvs2ir-constant op) arg-vartypes))
      (let* ((op-name (new-irvar))
	     (op-ir-type (pvs2ir-type (type op)))
	     (op-var (mk-ir-variable op-name op-ir-type))
	     (op-ir (pvs2ir* op bindings)))
	(if (ir-array? op-ir-type)
	    (mk-ir-let op-var op-ir
		       (mk-ir-let (car arg-vartypes)(car args-ir)
				  (mk-ir-lookup op-var (car arg-vartypes))))
	  (mk-ir-let op-var op-ir
		     (mk-ir-let* arg-vartypes
				 args-ir
				 (mk-ir-apply op-var arg-vartypes))))))))

(defmethod pvs2ir* ((expr list) bindings)
  (cond ((consp expr)
	 (cons (pvs2ir* (car expr) bindings)
	       (pvs2ir* (cdr expr) bindings)))
	(t nil)))

(defmethod pvs2ir* ((cexpr cases-expr) bindings)
  (pvs2ir* (translate-cases-to-if cexpr) bindings))

;;partial 
  ;; (with-slots (expr selections else-part) cexpr
  ;; 	      (let* ((adt (find-supertype (type expr)))
  ;; 		     (ir-selections (pvs2ir-selections selections adt))
  ;; 		     (ir-switch-else (pvs2ir* else-part bindings)))))
		
	      

    

(defmethod pvs2ir* ((expr if-expr) bindings)
  (cond ((branch? expr)
	 (let ((ifvar (mk-ir-variable (new-irvar) 'boolean))
	       (cond-ir (pvs2ir* (condition expr) bindings))
	       (then-ir (pvs2ir* (then-part expr) bindings))
	       (else-ir (pvs2ir* (else-part expr) bindings)))
	   (mk-ir-let  ifvar cond-ir
		       (mk-ir-ift ifvar then-ir else-ir))))
	(t (call-next-method))))

(defmethod pvs2ir* ((expr let-expr) bindings)
  (let ((let-bindings (bindings (operator expr)))
	(args (arguments expr))
	(expression (expression (operator expr))))
    (pvs2ir-let-expr let-bindings args expression bindings)))

(defun pvs2ir-let-expr (let-bindings args expression bindings)
  ;;deal with simple let-expressions first, and pattern matching lets later.
  (cond ((consp let-bindings)
	 (let* ((ir-var (new-irvar))
		(ir-type (pvs2ir-type (type (car let-bindings))))
		(ir-vartype (mk-ir-variable ir-var ir-type))
		(ir-bind-expr (pvs2ir* (car args) bindings)))
	   (mk-ir-let ir-vartype
		      ir-bind-expr 
		      (pvs2ir-let-expr (cdr let-bindings) (cdr args)
				       expression
				       (cons (cons (car let-bindings)
						   ir-vartype)
					     bindings)))))
	(t (pvs2ir* expression bindings))))

(defmethod pvs2ir* ((expr tuple-expr) bindings)
  (let* ((expressions (exprs expr))
	 (ir-assignments (pvs2ir*  expressions bindings))
	 (ir-field-vars (new-irvars (length expressions)))
	 (ir-field-types (pvs2ir-type (mapcar #'type expressions)))
	 (ir-field-var-types (mk-vartype-list  ir-field-vars
					       ir-field-types))
	 (ir-fields (loop for i from 1 to (length expressions)
			  as ir-var in ir-field-vars
			  collect
			  (mk-ir-field (intern (format nil "project_~a" i))
				       ir-var)))
	 (ir-recordtype (mk-ir-recordtype (loop for type in ir-field-types
						as field in ir-fields
						collect (mk-ir-fieldtype field type)))))
  (mk-ir-let* ir-field-var-types ir-assignments
	      (mk-ir-record ir-fields ir-recordtype))))


(defmethod pvs2ir* ((expr record-expr) bindings)
  (pvs2ir-fields (sort-assignments (assignments expr)) bindings))

(defun mk-vartype-list (vars types)
  (cond ((consp vars)(cons (mk-ir-variable (car vars)(car types))
			   (mk-vartype-list (cdr vars)(cdr types))))
	(t nil)))

(defmethod pvs2ir-expr-type ((expr number-expr))
  (mk-ir-subrange (number expr)(number expr)))

(defmethod pvs2ir-expr-type ((expr t))
  (pvs2ir-type (type expr)))

(defun pvs2ir-fields (assignments bindings)
  (let* ((expressions (mapcar #'expression assignments))
	 (ir-assignments (pvs2ir*  expressions bindings))
	 (ir-field-vars (new-irvars (length assignments)))
	 (ir-field-types (loop for expr in expressions
			       collect (pvs2ir-expr-type expr)))
	 (ir-field-vartypes (mk-vartype-list ir-field-vars ir-field-types))
	 (ir-fields (loop for assignment in assignments
			  as ir-field-vartype in ir-field-vartypes
			  collect
			  (mk-ir-field (id (caar (arguments assignment)))
				       ir-field-vartype)))
	 (ir-recordtype (mk-ir-recordtype (loop for field in ir-fields
						as type in ir-field-types
						collect (mk-ir-fieldtype (ir-fieldname field) type)))))
  (mk-ir-let* ir-field-vartypes ir-assignments
	      (mk-ir-record ir-fields ir-recordtype))))

(defmethod pvs2ir* ((expr fieldappl) bindings)
  (with-slots (id argument) expr
	      (let ((ir-argument (pvs2ir* argument bindings))
		    (argvar (mk-ir-variable (new-irvar)(pvs2ir-type (type argument)))))
		(mk-ir-let argvar
			   ir-argument
			   (mk-ir-get argvar id)))))

(defmethod pvs2ir* ((expr update-expr) bindings)
  (with-slots (type expression assignments) expr
	      (let ((ir-expression (pvs2ir* expression bindings)))
		(pvs2ir-update assignments ir-expression
			       (pvs2ir-type (type expression))
			       bindings))))

;;gets the type of component of nested arrays/records being updated.
;;This is used to get the right-hand side type of an update expression.
(defmethod get-component-ir-type ((ir-expr-type ir-funtype) lhs-args)
  (with-slots (ir-domain ir-range) ir-expr-type
	      (cond ((consp lhs-args)
		     (get-component-ir-type ir-range (cdr lhs-args)))
		    (t ir-expr-type))))

(defmethod get-component-ir-type ((ir-expr-type ir-recordtype) lhs-args)
  (with-slots (ir-field-types) ir-expr-type
	      (cond ((consp lhs-args)
		     (let* ((field-label (caar lhs-args))
			    (ir-field-type (if (accessor-assign? field-label)
				       (pvs2ir-type (range (type field-label)))
				     (let ((field-id (id field-label)))
				       (ir-ftype (find field-id ir-field-types :key #'ir-id))))))
		       (get-component-ir-type ir-field-type (cdr lhs-args))))
		    (t ir-expr-type))))

(defmethod get-component-ir-type ((ir-expr-type ir-typename) lhs-args)
  (with-slots (ir-type-id ir-type-defn) ir-expr-type
	      (get-component-ir-type ir-type-defn lhs-args)))

(defmethod get-component-ir-type ((ir-expr-type t) lhs-args)
  ;;lhs-args should be empty
  ir-expr-type)

;;evaluates the right-hand sides; creates bindings; and then constructs the
;;updates over the assignments
(defun pvs2ir-update (assignments ir-expression expression-type bindings)
  (let ((rhs-list (mapcar #'expression assignments))
	(lhs-list (mapcar #'arguments assignments)))
    (let* ((rhs-irvar-list (loop for i from 1 to (length rhs-list)
				 collect (new-irvar)))
	   (ir-rhs-types (loop for lhs in lhs-list
			    collect (get-component-ir-type expression-type lhs)))
	   (ir-rhs-vartypes (mk-vartype-list rhs-irvar-list ir-rhs-types))
	   (ir-rhs-list (loop for rhs in rhs-list
			      collect
			      (pvs2ir* rhs bindings)))
	   (ir-exprvar (mk-ir-variable (new-irvar) expression-type)))	;binds the ir-expression value
      (let ((ir-update-expr (pvs2ir-assignments lhs-list ;build updates
					       ir-rhs-vartypes
					       ir-exprvar
					       expression-type
					       bindings)))
	(mk-ir-let* ir-rhs-vartypes ir-rhs-list
		    (mk-ir-let ir-exprvar 
			       ir-expression
			       ir-update-expr))))))

;;iterates through the assignments constructing updates.  
(defun pvs2ir-assignments (lhs-list rhs-irvar-list
			       ir-exprvar ir-expr-type bindings)
  (cond ((consp lhs-list)
	 (let ((ir-assignment1
		(pvs2ir-assignment1 ir-expr-type
				    (car lhs-list)
				    (car rhs-irvar-list)
				    ir-exprvar bindings))
	       (ir-var1 (new-irvar)))
	   (let ((ir-vartype1 (mk-ir-variable ir-var1 ir-expr-type)))
	     (mk-ir-let  ir-vartype1 ir-assignment1
			 (pvs2ir-assignments (cdr lhs-list)(cdr rhs-irvar-list)
					     ir-vartype1 ir-expr-type bindings)))))
	(t ir-exprvar)))


;;The translation of A WITH [(i)(j):=v] becomes
;;let l1 = i
;;    e11 = A[i]
;;    e1 = A WITH [i := nil]    ;;to preserve reference count of A[i]
;;    en = e11 WITH [j := v]
;; in e1 WITH [i := en]
(defmethod pvs2ir-assignment1 ((ir-expr-type ir-funtype) lhs rhs-irvar ir-exprvar bindings)
  (cond ((consp lhs)
	 (let* ((ir-exprvar11 (new-irvar))
		(ir-expr-type11 (ir-range ir-expr-type))
		(ir-expr-vartype11 (mk-ir-variable ir-exprvar11 ir-expr-type11))
		(ir-rest-assignment (if (consp (cdr lhs))
					(pvs2ir-assignment1 ir-expr-type11
							    (cdr lhs)
							    rhs-irvar ir-expr-vartype11
							    bindings)
				      rhs-irvar))
		(lhs1 (caar lhs)))
	   (let ((lhs1-irvar (new-irvar))
		 (lhs1-ir (pvs2ir* lhs1 bindings)) ;;the index expression
		 (lhs1-ir-type (ir-domain ir-expr-type))
		 (ir-exprvar1 (new-irvar))
		 (ir-new-rhsvar (new-irvar)))
	     (let ((ir-lhs1-vartype (mk-ir-variable lhs1-irvar lhs1-ir-type))
		   (ir-expr-vartype1 (mk-ir-variable ir-exprvar1 ir-expr-type))
		   (ir-new-rhsvartype (mk-ir-variable ir-new-rhsvar ir-expr-type11)))
	       (mk-ir-let  ir-lhs1-vartype lhs1-ir
			   (mk-ir-let ir-expr-vartype11
				      (mk-ir-apply ir-exprvar (list ir-lhs1-vartype));;was lookup
				      (mk-ir-let ir-expr-vartype1
						 (if (ir-reference-type? ir-expr-type11)
						     (let* ((ir-nullvar (new-irvar))
							    (ir-nullvartype (mk-ir-variable ir-nullvar ir-expr-type11)))
						     (mk-ir-let ir-nullvartype
								(mk-ir-nil)
								(mk-ir-update ir-exprvar ir-lhs1-vartype ir-nullvartype)))
						   ir-exprvar)
						 (mk-ir-let ir-new-rhsvartype
							    ir-rest-assignment
							    (mk-ir-update ir-expr-vartype1 ir-lhs1-vartype ir-new-rhsvartype)))))))))
	(t ir-exprvar)))

(defmethod pvs2ir-assignment1 ((ir-expr-type ir-recordtype) lhs rhs-irvar ir-exprvar bindings)
    (cond ((consp lhs)
	   (let* ((lhs1 (caar lhs));;lhs1 is a field-name-expr
		  (ir-field-decl (find (id lhs1) (ir-field-types ir-expr-type) :key #'ir-id))
		  (ir-expr-type11 (pvs2ir-type (range (type lhs1)))) ;;(ir-ftype ir-field-decl))
		  (ir-exprvar11 (new-irvar))
		  (ir-expr-vartype11 (mk-ir-variable ir-exprvar11 ir-expr-type11))
		  (ir-rest-assignment (if (consp (cdr lhs))
					  (pvs2ir-assignment1 ir-expr-type11 (cdr lhs)
							      rhs-irvar ir-expr-vartype11
							      bindings)
					rhs-irvar)))
	     (let* ((ir-exprvar1 (new-irvar))
		    (ir-expr-vartype1 (mk-ir-variable ir-exprvar1 ir-expr-type))
		    (ir-new-rhsvar (new-irvar))
		    (ir-new-rhsvartype (mk-ir-variable ir-new-rhsvar ir-expr-type11)))
	       (mk-ir-let ir-expr-vartype11
			  (mk-ir-get ir-exprvar (id lhs1));;directly get the field
			  (mk-ir-let ir-expr-vartype1
				     (if (ir-reference-type? ir-expr-type11)
					 (let* ((ir-nullvar (new-irvar))
						(ir-nullvartype (mk-ir-variable ir-nullvar ir-expr-type11)))
					   (mk-ir-let ir-nullvartype
						      (mk-ir-nil)
						      (mk-ir-update ir-exprvar (id lhs1) ir-nullvartype)))
				       ir-exprvar)
				     (mk-ir-let ir-new-rhsvartype
						ir-rest-assignment
						(mk-ir-update ir-expr-vartype1 (id lhs1) ir-new-rhsvartype)))))))
	  (t ir-exprvar)))

(defmethod pvs2ir-assignment1 ((ir-expr-type ir-typename) lhs rhs-irvar ir-exprvar bindings)
  (pvs2ir-assignment1 (ir-type-defn ir-expr-type) lhs rhs-irvar ir-exprvar bindings))
					 
;;We are dealing with the simplified situation of types that are non-dependent
;;tuples, records, functions/arrays, and datatypes.  
(defun pvs2ir-type (type)
  (pvs2ir-type* type))

;;For the time being, translate types in a fully expanded form, and return to named types later. 
;; (defmethod pvs2ir-type* :around ((type type-expr))
;;   (if (type-name? (print-type type))
;;       (let* ((type-decl (declaration (print-type type)))
;; 	     (eval-type-info (ir-type-value type-decl)))
;; 	(if eval-type-info
;; 	    (ir-type-name eval-type-info)
;; 	  (let* ((ir-type-name (intern (format nil "~a_t" (gentemp (format nil "~a" (id type-decl))))))
;; 		 (eval-type-info (make-instance 'eval-type-info
;; 						:ir-type-name ir-type-name)))
;; 	    (setf (ir-type-value type-decl) ;;has to be done in this order
;; 		  eval-type-info) ;;so that the name is already there
;; 	    (let ((ir-type-definition (pvs2ir-type (type-value type-decl))))
;; 	      (setf (gethash ir-type-name *ir-type-def-hash*) ir-type-definition)
;; 	      (setf (ir-type-definition (ir-type-value type-decl)) ir-type-definition))
;; 	    ir-type-name)))
;;     (call-next-method)))

(defmethod pvs2ir-type* :around ((type type-expr))
  (if (type-name? (print-type type))
      (let ((type-decl (declaration (print-type type))));(break "around")
	(or (and (ir-type-value type-decl)
		 (ir-type-name (ir-type-value type-decl)))
	    (let* ((ir-type (call-next-method))
		   (ir-type-id (pvs2ir-unique-decl-id type-decl))
		   (ir-typename (mk-ir-typename ir-type-id ir-type)))
	      (setf (ir-type-value type-decl)
		    (mk-eval-type-info  ir-typename))
	      ir-typename)))
    (call-next-method)))

(defmethod pvs2ir-type* ((type funtype))
  (with-slots (domain range) type
	      (mk-ir-funtype (pvs2ir-type* domain)
			     (pvs2ir-type* range))))

(defmethod pvs2ir-type* ((type recordtype))
  (let ((fields (sort-fields (fields type))))
    (mk-ir-recordtype (pvs2ir-type* fields))))

(defmethod pvs2ir-type* ((type field-decl))
  (mk-ir-fieldtype (id type)(pvs2ir-type* (type type))))

(defmethod pvs2ir-type* ((type dep-binding))
  (pvs2ir-type* (type type)))

(defmethod pvs2ir-type* ((type tupletype))
  (let* ((types (types type))
	 (tuple-fields
	  (loop for typ in types as i from 1
		collect (mk-ir-fieldtype (intern (format nil "project_~a" i))
			       (pvs2ir-type* typ)))))
    (mk-ir-recordtype tuple-fields)))

(defmethod pvs2ir-type* ((type type-name))
  (if (tc-eq type *boolean*)
      'bool
    (pvs2ir-decl (declaration type))));;returns the type name

(defmethod pvs2ir-type* ((type list))
  (cond ((consp type)
	 (cons (pvs2ir-type* (car type))
	       (pvs2ir-type* (cdr type))))
	(t nil)))

(defmethod pvs2ir-type* ((type subtype))
  (cond ((tc-eq type *naturalnumber*) (mk-ir-subrange 0 '*))
	((tc-eq type *integer*) (mk-ir-subrange  '* '*))
	((tc-eq type *posint*)(mk-ir-subrange 1 '*))
	((tc-eq type *negint*)(mk-ir-subrange '* -1))
	((subtype-of? type *integer*)
	 (let ((sub (pvs2ir-subrange-index type)))
	   (if sub 
	       (mk-ir-subrange (car sub)(cadr sub))
	     (mk-ir-subrange '* '*))))
	(t (pvs2ir-type* (supertype type)))))

(defun intersect-subrange (sub1 sub2)
  (with-slots ((low1 ir-low) (high1 ir-high)) sub1
	      (with-slots ((low2 ir-low) (high2 ir-high)) sub2
			  (let ((new-low (if (eq low1 '*) low2
					   (if (eq low2 '*) low1
					     (if (< low1 low2) low2 low1))))
				(new-high (if (eq high1 '*) high2
					    (if (eq high2 '*) high1
					      (if (< high1 high2) high1 high2)))))
			    (mk-ir-subrange new-low new-high)))))

(defun pvs2ir-subrange-index (type)
  (let ((below (simple-below? type)))
    (if below
	(list 0 (if (number-expr? below)
		    (1- (number below))
		    '*))
	(let ((upto (simple-upto? type)))
	  (or (and upto (if (number-expr? upto)
			    (list 0 (number upto))
			  (let ((hihi (pvs2ir-subrange-index (type upto))))
			    (if hihi (list 0 (cadr hihi))
			      (list 0 '*)))))
	      (let ((x (simple-subrange? type)))
		(if x
		  (let ((lo (if (number-expr? (car x))
				(number (car x))
			      (let* ((type-ir (pvs2ir-type (type (car x))))
				     (judgement-type-irs (loop for type in (judgement-types (car x))
							       collect (pvs2ir-type type)))
				     (lo-subrange (loop for ir-type in (cons type-ir judgement-type-irs)
							when (and (ir-subrange? ir-type)(numberp (ir-low ir-type)))
							collect (ir-low ir-type))))
				(if lo-subrange (apply #'min lo-subrange) '*))))
			(hi (if (number-expr? (cdr x))
				(number (cdr x))
			      (let* ((type-ir (pvs2ir-type (type (car x))))
				     (judgement-type-irs (loop for type in (judgement-types (car x))
							       collect (pvs2ir-type type)))
				     (hi-subrange (loop for ir-type in (cons type-ir judgement-type-irs)
							when (and (ir-subrange? ir-type)(numberp (ir-high ir-type)))
						       collect (ir-high ir-type))))
				(if hi-subrange (apply #'max hi-subrange) '*)))))
		    (list lo hi))
		  (if (subtype-of? type *integer*)
		      (list '* '*)
		    (if (subtype? type)
			(pvs2ir-subrange-index (supertype type))
		      nil)))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmethod pvs2ir-freevars* :around ((ir-expr ir-expr))
  (with-slots (ir-freevars) ir-expr
	      (if (eq ir-freevars 'unbound)
		  (let ((ir-freevars (call-next-method)))
		    (setf (ir-freevars ir-expr) ir-freevars)
		    ir-freevars)
		ir-freevars)))

(defmethod pvs2ir-freevars* ((ir-expr ir-variable))
  (list ir-expr))

(defmethod pvs2ir-freevars* ((ir-expr ir-apply))
  (with-slots (ir-func ir-args) ir-expr
	      (union (pvs2ir-freevars* ir-func)
		     (pvs2ir-freevars* ir-args)
		     :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-let))
  (with-slots (ir-vartype ir-bind-expr ir-body) ir-expr
	      (union (pvs2ir-freevars* ir-bind-expr)
		     (remove ir-vartype (pvs2ir-freevars* ir-body) :test #'eq)
		     :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-record))
  (with-slots (ir-fields) ir-expr
	      (pvs2ir-freevars* ir-fields)))

(defmethod pvs2ir-freevars* ((ir-expr ir-field))
  (with-slots (ir-fieldname ir-value) ir-expr
	      (pvs2ir-freevars* ir-value)))

(defmethod pvs2ir-freevars* ((ir-expr ir-lambda))
  (with-slots (ir-vartypes ir-body) ir-expr
	      (set-difference (pvs2ir-freevars* ir-body)
			      ir-vartypes
			      :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-ift))
  (with-slots (ir-condition ir-then ir-else) ir-expr
	      (union (pvs2ir-freevars* ir-condition)
		     (union (pvs2ir-freevars* ir-then)
			    (pvs2ir-freevars* ir-else)
			    :test #'eq)
		     :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-nil))
  nil)

(defmethod pvs2ir-freevars* ((ir-expr ir-lookup))
  (with-slots (ir-array ir-index) ir-expr
	      (union (pvs2ir-freevars* ir-array)
		     (pvs2ir-freevars* ir-index)
		     :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-update))
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      (union (pvs2ir-freevars* ir-target)
		     (union (pvs2ir-freevars* ir-lhs)
			    (pvs2ir-freevars* ir-rhs)
			    :test #'eq)
		     :test #'eq)))

(defmethod pvs2ir-freevars* ((ir-expr ir-new))
  nil)

(defmethod pvs2ir-freevars* ((ir-expr ir-get))
  (with-slots (ir-record) ir-expr
	      (pvs2ir-freevars* ir-record)))

(defmethod pvs2ir-freevars* ((ir-expr list))
  (cond ((consp ir-expr)
	 (union (pvs2ir-freevars* (car ir-expr))
		(pvs2ir-freevars* (cdr ir-expr))
		:test #'tc-eq))
	(t nil)))

(defmethod pvs2ir-freevars* ((ir-expr t))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defcl ir-last (ir-expr)
  ir-var)

(defun mk-ir-last (ir-var)
  (make-instance 'ir-last
		 :ir-var ir-var))

(defmethod print-ir ((ir-expr ir-last))
  (with-slots (ir-var) ir-expr
  `(last ,(print-ir ir-var))))

(defcl ir-release (ir-expr) ;;these are the variables that should be freed on the then/else branches
  pre-ir-vars
  post-ir-vars
  ir-body)

(defun mk-ir-release (pre-ir-vars post-ir-vars ir-body)
  (make-instance 'ir-release
		 :pre-ir-vars pre-ir-vars
		 :post-ir-vars post-ir-vars
		 :ir-body ir-body))

(defmethod print-ir ((ir-expr ir-release))
  (with-slots (pre-ir-vars post-ir-vars ir-body) ir-expr
	      `(release ,(print-ir pre-ir-vars)
			,(print-ir post-ir-vars)
			,(print-ir ir-body))))

(defun get-assoc (var bindings)
  (let ((bnd (assoc var bindings)))
    (if bnd (cdr bnd) var)))

(defun apply-bindings (bindings var-list)
  (cond ((consp var-list)
	 (cons (get-assoc (car var-list) bindings)
	       (apply-bindings bindings (cdr var-list))))
	(t nil)))

(defun preprocess-ir (ir-expr)
  (preprocess-ir* ir-expr nil nil))

(defmethod preprocess-ir* ((ir-expr ir-variable) livevars bindings)
  (let* ((ir-var (get-assoc ir-expr bindings)))
    (if (memq ir-var livevars)
	ir-var ;;then variable is live and this is not the last occurrence
      (mk-ir-last ir-var))))

(defmethod preprocess-ir* ((ir-expr ir-apply) livevars bindings);;the ir-args are always distinct, but we are
  (with-slots (ir-func ir-args) ir-expr               ;;not exploiting this here. 
	      (mk-ir-apply (preprocess-ir* ir-func (union (apply-bindings bindings (pvs2ir-freevars* ir-args))
							  livevars
							  :test #'eq)
					   bindings)
			   (preprocess-ir* ir-args livevars bindings))))

;Irrelevant let-bindings are discarded
(defmethod preprocess-ir* ((ir-expr ir-let) livevars bindings)
  (with-slots (ir-vartype ir-bind-expr ir-body) ir-expr
	      (let ((body-freevars (pvs2ir-freevars* ir-body)))
		;(when (not (memq ir-vartype body-freevars)) (break "preprocess"))
		(if (memq ir-vartype body-freevars);;note: without apply-bindings
		    (let ((new-ir-bind-expr
			   (preprocess-ir* ir-bind-expr (union (apply-bindings bindings
												body-freevars)
								       livevars :test #'tc-eq)
							bindings)))
		      ;(break "preprocess ir-let: ~a" (ir-name ir-vartype))
		    (if (and (or (ir-variable? new-ir-bind-expr)
				 (ir-last? new-ir-bind-expr))
			     (ir2c-tequal* (ir-vtype ir-vartype)(ir-vtype (get-ir-last-var new-ir-bind-expr))))
			(preprocess-ir* ir-body livevars
					(acons ir-vartype
					       (get-assoc (get-ir-last-var new-ir-bind-expr) bindings)
					       bindings))
		      (let* ((new-ir-vartype
			      (if (ir-integer? new-ir-bind-expr)
				  (mk-ir-variable (ir-name ir-vartype)
						  (mk-ir-subrange (ir-intval ir-bind-expr)(ir-intval ir-bind-expr)))
				ir-vartype)))
			(mk-ir-let new-ir-vartype  new-ir-bind-expr
			     (preprocess-ir* ir-body livevars
					     (acons ir-vartype new-ir-vartype bindings))))))
		(preprocess-ir* ir-body livevars bindings)))))

(defmethod preprocess-ir* ((ir-expr ir-record) livevars bindings)
  (with-slots (ir-fields ir-recordtype) ir-expr
	      (mk-ir-record (preprocess-ir* ir-fields livevars bindings)
			    ir-recordtype)))

(defmethod preprocess-ir* ((ir-expr ir-field) livevars bindings)
  (with-slots (ir-fieldname ir-value) ir-expr
	      (mk-ir-field ir-fieldname (preprocess-ir* ir-value livevars bindings))))

(defmethod preprocess-ir* ((ir-expr ir-lambda) livevars bindings)
    (with-slots (ir-vartypes ir-rangetype ir-body) ir-expr
		(let* ((expr-freevars (pvs2ir-freevars* ir-expr))
		       (last-expr-freevars (set-difference expr-freevars livevars :test #'eq))
		       (other-livevars (union last-expr-freevars livevars :test #'eq))
		       (body-freevars (pvs2ir-freevars* ir-body))
		       (irrelevant-args (set-difference ir-vartypes body-freevars :test #'eq))
		       (preprocessed-body (preprocess-ir* ir-body other-livevars bindings))
		       (preprocessed-wrapped-body
			(if irrelevant-args
			    (mk-ir-release (extract-reference-vars irrelevant-args)
					   nil
					   preprocessed-body)
			  preprocessed-body))
		       (preprocessed-ir (mk-ir-lambda ir-vartypes
						      ir-rangetype
						      preprocessed-wrapped-body)))
		  ;; (format t "~%Preprocessing Lambda")
		  ;; (format t "~%Freevars = ~s" (print-ir expr-freevars))
		  ;; (format t "~%Irrelevant Args = ~s" (print-ir irrelevant-args))
		  ;; (format t "~%Non-live freevars = ~s" (print-ir last-expr-freevars))
		  (if last-expr-freevars
		      (mk-ir-release nil (extract-reference-vars last-expr-freevars)
				       preprocessed-ir)
		    preprocessed-ir))))

(defun extract-reference-vars (ir-varlist)
  (loop for ir-var in ir-varlist
	when (ir-reference-type? (ir-vtype ir-var))
	collect ir-var))


(defmethod preprocess-ir* ((ir-expr ir-ift) livevars bindings)
  (with-slots (ir-condition ir-then ir-else) ir-expr
	      (let* ((then-freevars (apply-bindings bindings (pvs2ir-freevars* ir-then)))
		     (then-marked (set-difference then-freevars livevars :test #'eq))		     
		     (else-freevars (apply-bindings bindings (pvs2ir-freevars* ir-else)))
		     (else-marked (set-difference else-freevars livevars :test #'eq))
		     (then-release (extract-reference-vars
				    (set-difference else-marked then-marked :test #'eq)))
		     (else-release (extract-reference-vars
				    (set-difference then-marked else-marked :test #'eq))))
		(mk-ir-ift (if (or (memq ir-condition livevars)
				   (memq ir-condition then-freevars)
				   (memq ir-condition else-freevars))
			       ir-condition
			     (mk-ir-last ir-condition))
			   (if then-release (mk-ir-release then-release nil (preprocess-ir* ir-then livevars bindings))
			     (preprocess-ir* ir-then livevars bindings))
			   (if else-release (mk-ir-release else-release nil (preprocess-ir* ir-else livevars bindings))
			     (preprocess-ir* ir-else livevars bindings))))))

(defmethod preprocess-ir* ((ir-expr ir-nil) livevars bindings)
  (declare (ignore livevars bindings))
  ir-expr)

(defmethod preprocess-ir* ((ir-expr ir-lookup) livevars bindings)
    (with-slots (ir-array ir-index) ir-expr
		(mk-ir-lookup (preprocess-ir* ir-array livevars bindings)
			      (preprocess-ir* ir-index livevars bindings))))

(defmethod preprocess-ir* ((ir-expr ir-update) livevars bindings)
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      (mk-ir-update (preprocess-ir* ir-target livevars bindings)
			    (preprocess-ir* ir-lhs livevars bindings)
			    (preprocess-ir* ir-rhs livevars bindings))))

(defmethod preprocess-ir* ((ir-expr ir-constructor-update) livevars bindings)
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      (mk-ir-constructor-update (preprocess-ir* ir-target livevars bindings)
			    (preprocess-ir* ir-lhs livevars bindings)
			    (preprocess-ir* ir-rhs livevars bindings))))

(defmethod preprocess-ir* ((ir-expr ir-new) livevars bindings)
  (declare (ignore livevars bindings))
  ir-expr)

(defmethod preprocess-ir* ((ir-expr ir-get) livevars bindings)
    (with-slots (ir-record ir-field) ir-expr
		(mk-ir-get (preprocess-ir* ir-record livevars bindings) ir-field)))

(defmethod preprocess-ir* ((ir-expr list) livevars bindings)
  (cond ((consp ir-expr)
	 (cons (preprocess-ir* (car ir-expr)
			       (union (apply-bindings bindings
						      (pvs2ir-freevars* (cdr ir-expr)))
				      livevars
				      :test #'eq)
			       bindings)
	       (preprocess-ir* (cdr ir-expr)
			       livevars bindings)))
	(t nil)))

(defmethod preprocess-ir* ((ir-expr t) livevars bindings)
  (declare (ignore livevars bindings))
  ir-expr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -------- C constants (implementation dependent) -------- from pvs2c-types.lisp
(defvar *min-C-int* (- (expt 2 31)))
(defvar *max-C-int* (- (expt 2 31) 1))
(defvar *min-C-uli* 0)
(defvar *max-C-uli* (- (expt 2 32) 1))

;;ir2c/ir2c* works by generating a list of statements for each ir expression.
;;One assumption through this is that whenever a PVS operation is being executed,
;;the data structures always contain non-NULL references, but this might not be
;;the case when an intermediate IR step is taken.  Either way, whenever an IR array/record
;;is released, any nested references are non-NULL and there is no need to check
;;for non-NULLity.

(defun mk-result-var (ir-type)
  (mk-ir-variable 'result ir-type))

(defun ir2c (ir-expr return-type);;this is called on a whole definition with a result
  (ir2c* ir-expr 'result (ir2c-type return-type)))

(defcl if-instr ()
  if-cond
  then-instr
  else-instr)

(defun mk-if-instr (if-cond then-instr else-instr)
  (make-instance 'if-instr
		 :if-cond if-cond
		 :then-instr then-instr
		 :else-instr else-instr))

(defcl for-instr ()
  for-index
  for-body)

(defun mk-for-instr (for-index for-body)
  (make-instance 'for-instr
		 :for-index for-index
		 :for-body for-body))

(defmethod ir2c* ((ir-expr symbol) return-var return-type)
  (let ((rhs (if (eq ir-expr 'TRUE) (format nil "~a" 'true)
	       (if (eq ir-expr 'FALSE) (format nil "~a" 'false)
		 (format nil "~a()" ir-expr)))))
    (list (format nil "~a = (~a_t)~a" return-var (print-ir return-type) rhs))))


(defmethod ir2c* ((ir-expr ir-integer) return-var return-type);;we need to handle number representations. 
  (with-slots (ir-intval) ir-expr
	      (list (format nil "~a = (~a_t)~a" return-var (print-ir return-type) ir-intval))))


(defmethod ir2c* ((ir-expr ir-last) return-var return-type)
  (with-slots (ir-var) ir-expr
	      (with-slots (ir-name) ir-var
			  (let ((c-return-type (add-c-type-definition (ir2c-type return-type))))
			    (list (format nil "~a = (~a_t)~a"  return-var c-return-type  ir-name))))))

(defmethod ir2c* ((ir-expr ir-variable) return-var return-type)
  (with-slots (ir-name ir-vtype) ir-expr
	      (if (ir-reference-type? ir-vtype)
		  (list (format nil "~a = (~a_t)~a" return-var (print-ir return-type)  ir-name) ;;assign then increment refcount
			(format nil "~a->count++" ir-name));;ir-name contains non-NULL
		(list (format nil  "~a = (~a_t)~a"  return-var (print-ir return-type) ir-name))) ;no reference count
	      ))	

(defmethod ir2c* ((ir-expr ir-record) return-var return-type)
  (with-slots (ir-fields ir-recordtype) ir-expr
	      (let ((ctype (add-c-type-definition (ir2c-type ir-recordtype))))
		 (cons (format nil "~a = new_~a();" return-var ctype)
		       (loop for fld in ir-fields
			     append
			     (with-slots (ir-fieldname ir-value) fld
					 (let ((rhs-var (get-ir-last-var ir-value)))
					   (cons (format nil "~a->~a = ~a"  return-var ir-fieldname (ir-name rhs-var))
						 (when (and (ir-reference-type? (ir-vtype rhs-var))
							    (not (ir-last? ir-value)))
						   (list (format nil "~a->count++" (ir-name rhs-var))))))))))))

(defun ir-record-field-type (rectype field)
  (with-slots (ir-field-types) rectype
	      (ir-record-field-type-rec ir-field-types field)))

(defun ir-record-field-type-rec (field-types field)
  (cond ((consp field-types)
	 (with-slots (ir-id ir-ftype) (car field-types)
		     (or (and (eq ir-id field)
			      ir-ftype)
			 (ir-record-field-type-rec (cdr field-types) field))))
	(t nil)))

(defmethod get-ir-type-value ((ir-type ir-typename))
  (with-slots (ir-type-id ir-type-defn) ir-type
	      (get-ir-type-value ir-type-defn)))

(defmethod get-ir-type-value ((ir-type t))
;  (break "get-ir-type-value")
  ir-type)


(defmethod ir2c* ((ir-expr ir-get) return-var return-type)
  (with-slots (ir-record ir-field) ir-expr
	      (let* ((ir-record-var (get-ir-last-var ir-record))
		     (assign-instr (format nil "~a = (~a_t)~a->~a"  return-var (print-ir return-type)
					       (ir-name ir-record-var)
					       ir-field))
		     (refcount-get-instr	;if lookup is a reference, first bump its count
		      (when (ir-reference-type? (ir-record-field-type (get-ir-type-value (ir-vtype ir-record-var)) ir-field))
			(list (format nil "~a->count++"  return-var))))
		     (release-record-instr
		      (when (ir-last? ir-record) ;if last, then release the array
			(list (format nil "release_~a(~a)"
				      (add-c-type-definition (ir2c-type (ir-vtype ir-record-var)))
				      (ir-name ir-record-var))))))
		(cons assign-instr (append refcount-get-instr release-record-instr)))))

  
(defvar *max-PVS-array-size* 32768);;Chosen arbitrarily to be 2^15, but tunable by the user

(defmethod ir-index? ((ir-typ ir-subrange))
  (with-slots (ir-low ir-high) ir-typ
	      (and (eql (ir-low ir-typ) 0)
		   (integerp ir-high)
		   (>= ir-high ir-low)
		   (< ir-high *max-PVS-array-size*)
		   (1+ ir-high))))

(defmethod ir-index? ((ir-type ir-typename))
  (with-slots (ir-type-defn) ir-type
	      (ir-index? ir-type-defn)))

(defmethod ir-index? ((ir-type t))
  nil)

(defmethod ir-array? ((ir-typ ir-funtype))
  (with-slots (ir-domain ir-range) ir-typ
	      (ir-index? ir-domain)));;add one to high to get array size

(defmethod ir-array? ((ir-typ ir-typename))
  (with-slots (ir-type-id ir-type-defn) ir-typ
	      (ir-array? ir-type-defn)))

(defmethod ir-array? ((ir-typ t))
  nil)

(defun get-ir-last-var (ir-last-or-var) ;;extracts the variable from (last x) or x. 
  (if (ir-last? ir-last-or-var)
      (ir-var ir-last-or-var)
    ir-last-or-var))

;;The reference counting on the last occurrence is done by the client: ir2c*(ir-apply)
(defun ir2c-function-apply (return-var return-type ir-function-name ir-args)
    (let* ((ir-arg-vars (loop for ir-var in ir-args
			      collect (get-ir-last-var ir-var)))
	   (ir-arg-var-names (loop for ir-var in ir-arg-vars
				   collect (ir-name ir-var))))
      (if (ir-primitive-op? ir-function-name)
	  (let ((instrs (ir2c-primitive-apply return-var return-type ir-function-name ir-arg-vars ir-arg-var-names)))
	    (format t "~%~a" instrs)
	    instrs)
	(let ((arg-string (format nil "~{~a~^, ~}" ir-arg-var-names)))
	  (list (format nil "~a = (~a_t)~a(~a)"  return-var (print-ir return-type) ir-function-name arg-string))))))

(defun gmp-suffix (c-type)
  (case c-type
    (int32 "_si")
    (uint32 "_ui")
    (t "")))

(defun ir-primitive-op? (ir-function-name)
  (memq ir-function-name *ir-primitives*))

(defun ir-primitive-arith-op? (ir-function-name)
  (memq ir-function-name *ir-arith-primitives*))

(defun tweak-equal (ir-function-name)
  (case ir-function-name
    (= '==)
    (t ir-function-name)))

(defun ir2c-primitive-apply (return-var return-type ir-function-name ir-args ir-arg-names)
  (cond ((ir-primitive-arith-op? ir-function-name);
	 (let ((c-arg-types (loop for ir-var in ir-args
				collect (ir2c-type (ir-vtype ir-var))))
	       (c-return-type (ir2c-type return-type))
	       (arity (length ir-args)))
	   ;(format t "~%c-arg-types: ~a" c-arg-types)
	   (case ir-function-name
	     (+ (ir2c-addition return-var c-return-type ir-arg-names c-arg-types))
	     (- (ir2c-subtraction return-var c-return-type ir-arg-names c-arg-types))
	     (* (ir2c-multiplication  return-var c-return-type ir-arg-names c-arg-types))
	     ((= < <= > >=) (ir2c-arith-relations (tweak-equal ir-function-name)
						  return-var
						  ir-arg-names c-arg-types))
	     (OR
	      (list (format nil "~a = ~a || ~a" return-var (car ir-arg-names) 
		      (cadr ir-arg-names))))
	     (AND
	      (list (format nil "~a = ~a && ~a" return-var (car ir-arg-names) 
			    (cadr ir-arg-names))))
	     (IMPLIES (list (format nil "~a = (!~a) ||  ~a" return-var (car ir-arg-names)
				    (cadr ir-arg-names))))
	     (WHEN (list (format nil "~a = ~a || ! ~a" return-var (car ir-arg-names)
				 (cadr ir-arg-names))))
	     (IFF (list (format nil "~a = (~a || ! ~a) && ((!~a) ||  ~a)" return-var
				(car ir-arg-names)  (cadr ir-arg-names)
				(car ir-arg-names)  (cadr ir-arg-names)))))))
	(t (break "not defined"))))

(defun ir2c-arith-relations (ir-function-name return-var
			      ir-arg-names c-arg-types)
  (let ((arg1 (car ir-arg-names))
	(arg2 (cadr ir-arg-names))
	(arg1-c-type (car c-arg-types))
	(arg2-c-type (cadr c-arg-types)))
    (let ((instrs 
    (ir2c-arith-relations-step ir-function-name return-var
			       arg1 arg1-c-type arg2 arg2-c-type)))
      ;(format t "ir2c-arith-relations-step: ~%~a" instrs)
      instrs)))

(defun ir2c-arith-relations-step
  (ir-function-name return-var
		    arg1 arg1-c-type arg2 arg2-c-type)
    (case arg1-c-type
      (int32 (case arg2-c-type
	       (int32 (list (format nil "~a = (~a ~a ~a)"
				    return-var arg1 ir-function-name arg2)))
	       (uint32 (list (mk-if-instr (format nil "(~a < 0)" arg1)
					  (list (format nil "~a = ~a"
						       return-var
						       (case ir-function-name
							 ((< <=) "true")
							 (t "false"))))
					  (list (format nil "~a = ((uint32_t)~a ~a ~a)"
							return-var 
							arg1 ir-function-name arg2)))))
	       (mpz (let ((tmp (gentemp "tmp")))
		      (list (format nil "int32_t ~a mpz_cmp_si(~a, ~a)" tmp arg2 arg1)
			    (format nil "~a = (~a ~a 0)" return-var tmp
				    (arith-relation-inverse ir-function-name)))))))
      (uint32 (case arg2-c-type
		(uint32  (list (format nil "~a = (~a ~a ~a)"
				       return-var arg1 ir-function-name arg2)))
		(mpz (let ((tmp (gentemp "tmp")))
		      (list (format nil "int32_t ~a mpz_cmp_ui(~a, ~a)" tmp arg2 arg1)
			    (format nil "~a = (~a ~a 0)" return-var tmp
				    (arith-relation-inverse ir-function-name)))))
		(t (ir2c-arith-relations-step (arith-relation-inverse ir-function-name)
								return-var
								arg2 arg2-c-type
								arg1 arg1-c-type))))
      (mpz (let ((tmp (gentemp "tmp")))
	     (list (format nil "int32_t ~a mpz_cmp~a(~a, ~a)" tmp
			   (case arg2-c-type (int32 'si)(uint32 'ui)(mpz ""))
			   arg2 arg1)
		   (format nil "~a = (~a ~a 0)" return-var tmp
			   ir-function-name))))))


(defun arith-relation-inverse (ir-relation)
  (case ir-relation
    (< '>=)
    (<= '>)
    (> '<=)
    (>= '<)))

(defun ir2c-addition (return-var c-return-type ir-args c-arg-types)
  (let ((arg1 (car ir-args))
	(arg2 (cadr ir-args))
	(arg1-c-type (car c-arg-types))
	(arg2-c-type (cadr c-arg-types)))
    (ir2c-addition-step return-var c-return-type arg1 arg1-c-type arg2 arg2-c-type)))

(defun ir2c-addition-step (return-var c-return-type arg1 arg1-c-type arg2 arg2-c-type)
  (case arg1-c-type
    (uint32 (case arg2-c-type
		  (uint32 (case c-return-type
			      (uint32
			       (list (format nil "~a = ~a + ~a" return-var arg1 arg2)))
			      (int32 (format nil "~a = (int32_t) (~a + ~a)" return-var arg1 arg2))
			      (mpz (list (format nil "mpz_set_ui(~a, ~a)"
						   return-var arg1)
					   (format nil "mpz_add_ui(~a, ~a, ~a)" return-var return-var arg2)))
			      (mpq (break "deal with this later"))))
		  (int32 (case c-return-type
			   (uint32 
			    (list (format nil "if (~a < 0){~a =  (~a - (~a_t)(-~a));} else {~a =  (~a + (~a_t)~a);}"
					     arg2
					     return-var arg1 c-return-type
					     arg2
					     return-var arg1 c-return-type arg2)))
			   (int32 (list (format nil "if (~a < 0){if ((uint32_t)(-~a) <= ~a){~a = (int32_t)(~a - (uint32_t)(-~a));} else {~a = (int32_t)~a + ~a;};} else {~a = (int32_t)(~a + (uint32_t)~a);}"
					     arg2 arg2 arg1 return-var arg1 arg2
					     return-var arg1 arg2
					     return-var arg1 arg2)))
			   (mpz (list (format nil "mpz_set_ui(~a, ~a)" return-var arg1)
				      (format nil "if (~a < 0){mpz_sub_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_add_ui(~a, ~a (uint32_t)(~a));}"
					      arg2
					      return-var return-var arg2
					      return-var return-var arg2)))))
		  (mpz (let ((tmp (gentemp "tmp")))
			 (case c-return-type
			   ((uint32 int32)
			    (ir2c-addition-step  return-var c-return-type arg2 arg2-c-type
				      arg1 arg1-c-type))
			   (mpz (list (format nil "mpz_set_ui(~a, ~a)" return-var arg1)
				      (format nil "mpz_add(~a, ~a, ~a)" return-var return-var arg2))))))))
      (int32 (case arg2-c-type
	       (int32 (case c-return-type
			(uint32 (list (format nil "~a = (~a_t) (~a + ~a)"
					      return-var c-return-type arg1 arg2)))
			(int32 (list (format nil "~a = ~a + ~a"
					     return-var arg1 arg2)))
			(mpz (list (format nil "mpz_set_si(~a, ~a)" return-var arg1)
				   (format nil "if (~a < 0){mpz_sub_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_add_ui(~a, ~a (uint32_t)(~a));}"
					      arg2
					      return-var return-var arg2
					      return-var return-var arg2)))))
	       (t (ir2c-addition-step return-var c-return-type arg2 arg2-c-type
				      arg1 arg1-c-type ))))
      (mpz (case c-return-type
	     ((uint32 int32)
	      (case arg2-c-type
		(uint32 (ir2c-addition-step return-var c-return-type arg2 arg2-c-type
					      arg1 arg1-c-type))
		(int32 (let ((tmp (gentemp "tmp")))
			 (list (format nil "mpz_t ~a" tmp)
			       (format nil "mpz_init(~a)" tmp)
			       (format nil "if (~a < 0){mpz_sub_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_add_ui(~a, ~a, (uint32_t)(~a));}"
				       arg2
				       tmp arg1 arg2
				       tmp arg1 arg2)
			       (format nil "~a = mpz_get~a(~a)"
				       return-var
				       (gmp-suffix c-return-type)
				       tmp)
			       (format nil "mpz_clear(~a)" tmp))))
		(mpz (let ((tmp (gentemp "tmp")))
		       (list (format nil "mpz_t ~a" tmp)
			     (format nil "mpz_init(~a)" tmp)
			     (format nil "mpz_add(~a, ~a, ~a)"
				     tmp arg1 arg2)
			     (format nil "~a = mpz_get~a(~a, ~a)"
				     return-var
				     (gmp-suffix c-return-type)
				     tmp)
			     (format nil "mpz_clear(~a)" tmp))))))
	     (mpz (list (format nil "mpz_set~a(~a, ~a)"
				(gmp-suffix arg2-c-type)
				return-var arg2)
			(format nil "mpz_add(~a, ~a, ~a)"
				return-var return-var arg1)))))))

(defun ir2c-subtraction (return-var c-return-type ir-args c-arg-types)
  (let ((arg1 (car ir-args))
	(arg2 (cadr ir-args))
	(arg1-c-type (car c-arg-types))
	(arg2-c-type (cadr c-arg-types)))
    (ir2c-subtraction-step return-var c-return-type arg1 arg1-c-type arg2 arg2-c-type)))

(defun ir2c-subtraction-step (return-var c-return-type arg1 arg1-c-type arg2 arg2-c-type)
  (case arg1-c-type
    (uint32 (case arg2-c-type
		  (uint32 (case c-return-type
			      (uint32
			       (list (format nil "~a = ~a - ~a" return-var arg1 arg2)))
			      (int32 ;;checked that this (below) works in C
			       (format nil "~a = (int32_t) (~a - ~a)" return-var arg1 arg2))
			      (mpz (list (format nil "mpz_set_ui(~a, ~a)"
						   return-var arg1)
					   (format nil "mpz_sub_ui(~a, ~a, ~a)" return-var return-var arg2)))
			      (mpq (break "deal with this later"))))
		  (int32 (case c-return-type
			   (uint32 
			    (list (format nil "if (~a < 0){~a =  (~a + (~a_t)(-~a));} else {~a =  (~a - (~a_t)~a);}"
					     arg2
					     return-var arg1 c-return-type
					     arg2
					     return-var arg1 c-return-type arg2)))
			   (int32 (list (format nil "if (~a < 0){if ((uint32_t)(-~a) <= ~a){~a = (int32_t)(~a + (uint32_t)(-~a));} else {~a = (int32_t)~a - ~a;};} else {~a = (int32_t)(~a - (uint32_t)~a);}"
					     arg2 arg2 arg1 return-var arg1 arg2
					     return-var arg1 arg2
					     return-var arg1 arg2)))
			   (mpz (list (format nil "mpz_set_ui(~a, ~a)" return-var arg1)
				      (format nil "if (~a < 0){mpz_add_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_sub_ui(~a, ~a (uint32_t)(~a));}"
					      arg2
					      return-var return-var arg2
					      return-var return-var arg2)))))
		  (mpz (let ((tmp (gentemp "tmp")))
			 (case c-return-type
			   ((uint32 int32)
			    (ir2c-subtraction-step  return-var c-return-type arg2 arg2-c-type
				      arg1 arg1-c-type))
			   (mpz (list (format nil "mpz_set_ui(~a, ~a)" return-var arg1)
				      (format nil "mpz_sub(~a, ~a, ~a)" return-var return-var arg2))))))))
      (int32 (case arg2-c-type
	       (int32 (case c-return-type
			(uint32 (list (format nil "~a = (~a_t) (~a - ~a)"
					      return-var c-return-type arg1 arg2)))
			(int32 (list (format nil "~a = ~a - ~a"
					     return-var arg1 arg2)))
			(mpz (list (format nil "mpz_set_si(~a, ~a)" return-var arg1)
				   (format nil "if (~a < 0){mpz_add_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_sub_ui(~a, ~a (uint32_t)(~a));}"
					      arg2
					      return-var return-var arg2
					      return-var return-var arg2)))))
	       (t (ir2c-subtraction-step return-var c-return-type arg2 arg2-c-type
				      arg1 arg1-c-type ))))
      (mpz (case c-return-type
	     ((uint32 int32)
	      (case arg2-c-type
		(uint32 (ir2c-subtraction-step return-var c-return-type arg2 arg2-c-type
					      arg1 arg1-c-type))
		(int32 (let ((tmp (gentemp "tmp")))
			 (list (format nil "mpz_t ~a" tmp)
			       (format nil "mpz_init(~a)" tmp)
			       (format nil "if (~a < 0){mpz_add_ui(~a, ~a, (uint32_t)(-~a));} else {mpz_sub_ui(~a, ~a, (uint32_t)(~a));}"
				       arg2
				       tmp arg1 arg2
				       tmp arg1 arg2)
			       (format nil "~a = mpz_get~a(~a)"
				       return-var
				       (gmp-suffix c-return-type)
				       tmp)
			       (format nil "mpz_clear(~a)" tmp))))
		(mpz (let ((tmp (gentemp "tmp")))
		       (list (format nil "mpz_t ~a" tmp)
			     (format nil "mpz_init(~a)" tmp)
			     (format nil "mpz_sub(~a, ~a, ~a)"
				     tmp arg1 arg2)
			     (format nil "mpz_get~a(~a, ~a)"
				     (gmp-suffix c-return-type)
				     return-var tmp)
			     (format nil "mpz_clear(~a)" tmp))))))
	     (mpz (list (format nil "mpz_set~a(~a, ~a)"
				(gmp-suffix arg2-c-type)
				return-var arg2)
			(format nil "mpz_sub(~a, ~a, ~a)"
				return-var return-var arg1)))))))

							   
			   


(defun mpnumber-type? (c-type)
  (or (eq c-type 'mpz)(eq c-type 'mpq)))

(defmethod ir2c* ((ir-expr ir-lookup) return-var return-type)
  (with-slots (ir-array ir-index) ir-expr
	      (let* ((ir-array-var (get-ir-last-var ir-array))
		     (ir-index-var (get-ir-last-var ir-index))
		     (assign-instr (format nil "~a = (~a_t)~a->elems[~a]"  return-var (print-ir return-type)
					       (ir-name ir-array-var)
					       (ir-name ir-index-var)))
		     (refcount-lookup-instr	;if lookup is a reference, first bump its count
		      (when (ir-reference-type? (ir-range (get-ir-type-value (ir-vtype ir-array-var))))
			(list (format nil "~a->count++"  return-var))))
		     (release-array-instr
		      (when (ir-last? ir-array) ;if last, then release the array
			(list (format nil "release_~a(~a)"
				      (add-c-type-definition (ir2c-type (ir-vtype ir-array-var)))
				      (ir-name ir-array-var))))))
		(cons assign-instr (append refcount-lookup-instr release-array-instr)))))
	      

(defmethod ir2c* ((ir-expr ir-apply) return-var return-type)
  (with-slots (ir-func ir-args) ir-expr
	      (let* ((ir-func-var (get-ir-last-var ir-func))
		     (hi-array (when (ir-variable? ir-func-var)
				 (ir-array? (ir-vtype ir-func-var))))
		     (ir-index-var (when hi-array (get-ir-last-var (car ir-args)))))
	      (if hi-array;;assuming no closure invocations for now
		  (let* ((assign-instr (format nil "~a = (~a_t)~a->elems[~a]"  return-var (print-ir return-type)
					       (ir-name ir-func-var)
					       (ir-name ir-index-var)))
			 (refcount-lookup-instr	;if lookup is a reference, first bump its count
			  (when (ir-reference-type? (ir-range (get-ir-type-value (ir-vtype ir-func-var))))
			    (list (format nil "~a->count++"  return-var))))
			 (release-array-instr
			  (when (ir-last? ir-func) ;if last, then release the array
			    (list (format nil "release_~a(~a)"
					  (add-c-type-definition (ir2c-type (ir-vtype ir-func-var)))
					  (ir-name ir-func-var))))))
		    (cons assign-instr (append refcount-lookup-instr release-array-instr)))
		;;otherwise, it's a function call
	      (let* ((invoke-instrs (ir2c-function-apply return-var return-type ir-func-var ir-args))
		     ;; (rhs-string (format nil "~a(~{~a~^, ~})" ir-func-var ir-arg-vars))
		     ;; (invoke-instr (format nil "~a = ~a" return-var rhs-string))
		     (release-instrs (loop for ir-var in ir-args ;;bump the counts of non-last references by one
					   when (and (not (ir-last? ir-var))(ir-reference-type? (ir-vtype ir-var)))
					   collect (format nil "~a->count++" (ir-name ir-var)))))
		;(break "ir-apply")
		(append release-instrs invoke-instrs))))))

(defmethod ir2c* ((ir-expr ir-let) return-var return-type)
  (with-slots (ir-vartype ir-bind-expr ir-body) ir-expr
	      (with-slots (ir-name ir-vtype) ir-vartype
			  (let* ((var-ctype (add-c-type-definition (ir2c-type ir-vtype)))
				 (decl-instr (format nil "~a_t ~a" var-ctype ir-name));;need mpz_init/release for mpz_t
				 (bind-instrs (ir2c* ir-bind-expr ir-name 
						     var-ctype))  ;(ir2c-type (ir-vtype ir-vartype))
				 (body-instrs (ir2c* ir-body return-var return-type)));(break "ir-let")
			    (cons decl-instr (append bind-instrs body-instrs))))))

(defmethod ir2c* ((ir-expr ir-nil) return-var return-type)
  (list (format nil "~a = NULL" return-var)))

(defmethod ir2c-type ((ir-typ ir-subrange))
  (with-slots (ir-low ir-high) ir-typ
	      (cond ((and (integerp ir-low)
			  (>= ir-low *min-C-uli*)
			  (integerp ir-high)
			  (<= ir-high *max-C-uli*))
		     'uint32)
		    ((and (integerp ir-low)
			  (>= ir-low *min-C-int*)
			  (integerp ir-high)
			  (<= ir-high *max-C-int*))
		     'int32
		     'mpz))))

(defun ir-integer-type? (ir-typ)
  (and (ir-subrange? ir-typ)
       (with-slots (ir-low ir-high) ir-typ
		   (or (and (>= ir-low *min-C-uli*)
			    (<= ir-high *max-C-uli*))
		       (and (>= ir-low *min-C-int*)
			    (<= ir-high *max-C-int*))))))

;;The ir-array is a class
(defcl ir-arraytype (ir-type)
  size
  elemtype);later on, we could add an offset

(defun mk-ir-arraytype (size elemtype)
  (make-instance 'ir-arraytype
		 :size size
		 :elemtype elemtype))

(defmethod print-ir ((ir-type ir-arraytype))
  (with-slots (size elemtype) ir-type
	      (format nil "~a[~d]" (print-ir elemtype) size)))

(defmethod ir2c-type ((ir-typ ir-funtype))
  (with-slots (ir-domain ir-range) ir-typ
	      (let ((size (ir-index? ir-domain)))
		(if size ;;check that size is below max-PVS-array-size
		    (mk-ir-arraytype size (ir2c-type ir-range))
		  (mk-ir-funtype  (ir2c-type ir-domain)
				  (ir2c-type ir-range))))))

(defmethod ir2c-type ((ir-typ ir-recordtype))
  (with-slots (ir-field-types) ir-typ
	      (mk-ir-recordtype
	       (ir2c-type-fields ir-field-types))))

(defmethod ir2c-type ((ir-typ ir-adt-recordtype))
  (with-slots (ir-field-types ir-constructors) ir-typ
	      (mk-ir-adt-recordtype
	       (ir2c-type-fields ir-field-types)
	       ir-constructors)))

(defmethod ir2c-type ((ir-typ ir-adt-constructor-recordtype))
  (with-slots (ir-field-types ir-adt-name) ir-typ
	      (mk-ir-adt-constructor-recordtype
	       (ir2c-type-fields ir-field-types)
	       ir-adt-name)))

(defun ir2c-type-fields (ir-field-types)
  (cond ((consp ir-field-types)
	 (with-slots (ir-id ir-ftype) (car ir-field-types)
		     (cons (mk-ir-fieldtype ir-id
					    (ir2c-type ir-ftype))
			   (ir2c-type-fields (cdr ir-field-types)))))
	(t nil)))

(defmethod ir2c-type ((ir-type symbol))
  (case ir-type
    (boolean 'bool)
    (t ir-type)))

(defmethod ir2c-type ((ir-type ir-typename))
  (with-slots (ir-type-id ir-type-defn) ir-type
	      (let ((tdefn (ir2c-type ir-type-defn)))
		(if (symbolp tdefn) ;;i.e., it's a primitive
		    tdefn
		  (mk-ir-typename ir-type-id tdefn)))))

(defmethod ir2c-type ((ir-type t))
  ir-type)


(define-condition pvs2c-error (simple-error) (error-string))

	      ;; (let ((array? (ir-array? ir-domain))
	      ;; 	    ) ;; ignoring non-arrays for now
	      ;; 	(if (ir-integer-type? ir-range)
	      ;; 	    (format nil "ref_int_t")
	      ;; 	  (format nil "ref_ref_t")))))


;;A lambda-expression turns into the initialization for an array.  
(defmethod ir2c* ((ir-expr ir-lambda) return-var return-type)
  (with-slots (ir-vartypes ir-rangetype ir-body) ir-expr
	    (let ((array? (and (eql (length ir-vartypes) 1)
				(ir-index? (ir-vtype (car ir-vartypes))))))     
	      (if array?
		  (let* ((ir-arraytype (mk-ir-arraytype array? (ir2c-type ir-rangetype)))
			 (c-arraytype (add-c-type-definition ir-arraytype))
			 (index (ir-name (car ir-vartypes)))
			 (return-location (format nil "~a->elems[~a]" return-var index))
			 (return-location-type (add-c-type-definition (ir2c-type ir-rangetype)))
			(c-body (ir2c* ir-body return-location return-location-type)))
		    (with-slots (size elemtype) ir-arraytype
				(list (format nil "~a = new_~a()" return-var c-arraytype)
				      ;(format nil "~a->count = 1");;this should be done within new.
				      (mk-for-instr (format nil "uint32_t ~a = 0; ~a < ~a; ~a++"
					      index index size index)
					      c-body))))
		(error 'pvs2c-error :format-control "closures not yet implemented")))))

(defmethod ir2c* ((ir-expr ir-ift) return-var return-type)
  (with-slots (ir-condition ir-then ir-else) ir-expr
	      (let ((c-then-instrs (ir2c* ir-then return-var return-type))
		    (c-else-instrs (ir2c* ir-else return-var return-type)))
		(list (mk-if-instr 
		       (ir-name (get-ir-last-var ir-condition))
		       c-then-instrs
		       c-else-instrs)))))

(defmethod ir2c* ((ir-expr ir-release) return-var return-type)
  (with-slots (pre-ir-vars post-ir-vars ir-body) ir-expr
	      (let ((c-body (ir2c* ir-body return-var return-type))
		    (pre-release-instrs (loop for vartype in pre-ir-vars
					  collect (format nil "release_~a(~a)"
							  (add-c-type-definition (ir2c-type (ir-vtype vartype)))
							  (ir-name vartype))))
		    (post-release-instrs (loop for vartype in post-ir-vars
					  collect (format nil "release_~a(~a)"
							  (add-c-type-definition (ir2c-type (ir-vtype vartype)))
							  (ir-name vartype)))))
		(append pre-release-instrs c-body post-release-instrs))))

(defmethod ir2c* ((ir-expr ir-new) return-var return-type)
  (with-slots (ir-etype) ir-expr
	      (ir2c-new ir-etype return-var)))

(defmethod ir2c-new ((ir-type ir-arraytype) return-var)
  (with-slots (size elemtype) ir-type
	      (let ((ctype (add-c-type-definition (ir2c-type ir-type))))
		(format nil "~a = new_~a()" return-var ctype))))

(defmethod ir2c-new ((ir-type ir-recordtype) return-var)
  (let ((ctype (add-c-type-definition (ir2c-type ir-type))))
    (format nil "~a = new_~a()" return-var ctype)))

(defmethod ir2c* ((ir-expr ir-update) return-var return-type)
  (with-slots (ir-target ir-lhs ir-rhs) ir-expr
	      (let* ((target-var (get-ir-last-var ir-target))
		     (target-var-name (ir-name target-var))
		     (rhs-var (get-ir-last-var ir-rhs))
		     (rhs-var-name (ir-name rhs-var))
		     (ir-ctype (ir2c-type (ir-vtype target-var)))
		     (ctype (add-c-type-definition ir-ctype))
		     (creturn-type (add-c-type-definition (ir2c-type return-type)))
		     (target-last (ir-last? ir-target))
		     (rhs-last (and (not (ir-constructor-update? ir-expr))
				    (ir-last? ir-rhs)
				    (ir-reference-type? (ir-vtype rhs-var))))
		     (rhs-last-instr (if rhs-last
					(list (format nil "if (~a != NULL) ~a->count--"
						      rhs-var-name rhs-var-name))
				       nil)))
		(when (ir-constructor-update? ir-expr)(break "ir2c*(ir-constructor-update)"))
		(if (ir-arraytype? (get-ir-type-value ir-ctype))
		    (let* ((lhs-var (get-ir-last-var ir-lhs))
			   (lhs-var-name (ir-name lhs-var)))
		      (if target-last
			  (cons (format nil "~a = (~a_t)update_~a(~a, ~a, ~a)"
					return-var creturn-type ctype target-var-name lhs-var-name rhs-var-name)
				rhs-last-instr)
			(cons (format nil "{~a = (~a_t)copy_~a(~a); update_~a(~a, ~a, ~a)}"
				      return-var creturn-type ctype target-var-name ctype
				       return-var  lhs-var-name rhs-var-name)
			      rhs-last-instr)))
		  ;;else we're assuming it's a record
		  (if target-last
		      (cons (format nil "~a = (~a_t)update_~a_~a(~a, ~a)"
					return-var creturn-type ctype ir-lhs target-var-name rhs-var-name)
			    rhs-last-instr)
		    (cons (format nil "{~a = (~a_t)copy_~a(~a); ~a = (~a_t)update_~a_~a(~a, ~a);}"
				  return-var creturn-type ctype target-var-name
				  return-var creturn-type ctype ir-lhs target-var-name rhs-var-name)
			  rhs-last-instr))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;process a type into its C definition relative to *c-type-info-table*

(defcl c-defn-info ()
  op-name
  op-header
  op-defn)

(defun mk-c-defn-info (op-name op-header op-defn)
  (make-instance 'c-defn-info
		 :op-name op-name
		 :op-header op-header
		 :op-defn op-defn))

(defcl c-type-info ()
  ir-texpr
  tname
  tdefn
  new-info
  release-info
  copy-info 
  update-info)

(defcl simple-c-type-info ()
  ir-texpr tname tdefn)

(defvar *c-type-info-table* nil) ;;a list of c-type-info
(defvar *ir-type-info-table* nil) ;;a list of ir-typenames

(defun get-c-type-info (ir-texpr)
  (find ir-texpr *c-type-info-table* :key #'ir-texpr :test #'ir2c-tequal))

(defun get-c-type-info-by-name (tname)
  (find tname *c-type-info-table* :key #'tname))

(defun mk-simple-c-type-info (ir-texpr tname tdefn)
  (make-instance 'simple-c-type-info
		   :ir-texpr ir-texpr
		   :tname tname
		   :tdefn tdefn))

(defun mk-c-type-info (ir-texpr tname tdefn new-info release-info copy-info update-info)
  (make-instance 'c-type-info
		   :ir-texpr ir-texpr
		   :tname tname
		   :tdefn tdefn
		   :new-info new-info
		   :release-info release-info
		   :copy-info copy-info
		   :update-info update-info))

(defmethod add-c-type-definition ((ir2c-type t) &optional tname)
  (cond (tname
	 (let ((c-type-info (get-c-type-info-by-name tname)))
	   (when (null ir2c-type) (break "add-c-type-definition"))
	   (cond (c-type-info tname)
		 (t (push (mk-simple-c-type-info ir2c-type tname (format nil "typedef ~a_t ~a_t;" ir2c-type tname))
			  *c-type-info-table*)
		    tname))))
	(t ir2c-type)))

(defmethod add-c-type-definition ((ir2c-type ir-typename) &optional tname) ;;tname is ignored
  (with-slots (ir-type-id ir-type-defn) ir2c-type
	      ;(break "add-c-type-definition ir-typename")
	     (add-c-type-definition  (ir2c-type ir-type-defn) ir-type-id)))


(defmethod add-c-type-definition ((ir2c-type ir-arraytype) &optional tname)
  (with-slots (size elemtype) ir2c-type
	      (let* ((c-type-info (get-c-type-info ir2c-type))
		     (c-type-name (when c-type-info (tname c-type-info))))
		(or c-type-name
		    (let* ((c-range-root (add-c-type-definition elemtype))
			   (type-name-root (or tname (format nil "c_array_~a" (length *c-type-info-table*))))
			   (type-name (intern (format nil "~a_t" type-name-root)))
			   (struct-name (intern (format nil "~a_s" type-name-root)))
			   (type-defn (format nil "struct ~a { uint32_t count;~% ~a_t elems[~a]; };~%typedef struct ~a * ~a;"
					      struct-name c-range-root size struct-name type-name)));(break "add-c-type")
		      (let* ((new-info (make-array-new-info type-name-root size elemtype))
			     (release-info (make-array-release-info type-name-root size elemtype c-range-root))
			     (copy-info (make-array-copy-info type-name-root size elemtype))
			     (update-info (list (make-array-update-info type-name-root elemtype))))
			(push (mk-c-type-info ir2c-type type-name-root type-defn new-info release-info copy-info update-info)
			      *c-type-info-table*)
			type-name-root))))))

(defun make-array-new-info (type-name-root size elemtype)
  (let* ((new-name (intern (format nil "new_~a" type-name-root)))
	 (new-header (make-new-header new-name type-name-root))
	 (new-defn (make-array-new-defn new-name type-name-root size elemtype)))
    (mk-c-defn-info new-name new-header new-defn)))

(defun make-new-header (new-name type-name-root)
  (format nil "extern ~a_t ~a(void);" type-name-root new-name))

(defun make-array-new-defn (new-name type-name-root size ir-range) 
  (if (ir-reference-type? ir-range)
      (format nil "~a_t ~a(){~%~8T~a_t tmp = (~a_t) malloc(sizeof(struct ~a_s));~%~8Ttmp->count = 1;~%~8Treturn tmp;}"
	      type-name-root new-name type-name-root type-name-root type-name-root)
      (format nil "~a_t ~a(){~%~8T~a_t tmp = (~a_t) malloc(sizeof(struct ~a_s));~%~8Ttmp->count = 1;~%~8T return tmp;}"
	      type-name-root new-name type-name-root type-name-root type-name-root)))

(defun make-array-release-info (type-name-root size elemtype c-range-root)
  (let* ((release-name (intern (format nil "release_~a" type-name-root)))
	 (release-header (make-array-release-header release-name type-name-root))
	 (release-defn (make-array-release-defn release-name type-name-root size elemtype c-range-root)))
    (mk-c-defn-info release-name release-header release-defn)))

(defun make-array-copy-info (type-name-root size elemtype)
  (let* ((copy-name (intern (format nil "copy_~a" type-name-root)))
	 (copy-header (make-array-copy-header copy-name type-name-root))
	 (copy-defn (make-array-copy-defn copy-name type-name-root size elemtype)))
    (mk-c-defn-info copy-name copy-header copy-defn)))


(defun make-array-update-info (type-name-root elemtype)
  (let* ((update-name (intern (format nil "update_~a" type-name-root)))
	 (update-header (make-array-update-header update-name type-name-root elemtype))
	 (update-defn (make-array-update-defn update-name type-name-root elemtype)))
    (mk-c-defn-info update-name update-header update-defn)))
					     
(defmethod ir-reference-type? ((ir-type ir-arraytype))
  t)

(defmethod ir-reference-type? ((ir-type ir-funtype));an array or closure
  t)

(defmethod ir-reference-type? ((ir-type ir-recordtype))
  t)

(defmethod ir-reference-type? ((ir-type ir-typename))
  (with-slots (ir-type-id ir-type-defn) ir-type
	      (ir-reference-type? ir-type-defn)))

(defmethod ir-reference-type? ((ir-type t))
  nil)

(defun make-array-release-header (release-name type-name)
  (format nil "extern void ~a(~a_t x);" release-name type-name))
;;The release operation reduces the reference count of a reference by one, and frees the object
;;(releasing any connected objects) if the count falls to 0.  
(defun make-array-release-defn (release-name type-name-root size ir-range c-range-root)
  (if (ir-reference-type? ir-range)
      (format nil "void ~a(~a_t x){~%~8Tx->count--;~%~8T if (x->count <= 0){~%~16Tfor (int i = 0; i < ~a; i++){release_~a(x->elems[i]);};~%~8Tfree(x);}~%}"
	      release-name type-name-root size c-range-root)
    ;if there are nested references, these need to be released before freeing x,
    ;;otherwise, just free x.
    (format nil "void ~a(~a_t x){~%~8Tx->count--;~%~8T if (x->count <= 0){free(x);}~%}"
	    release-name type-name-root)))

(defun make-array-copy-header (copy-name type-name-root)
  (format nil "extern ~a_t ~a(~a_t x);" type-name-root copy-name type-name-root))

(defun make-array-copy-defn (copy-name type-name-root size elemtype)
  (let ((copy-instr (if (ir-reference-type? elemtype)
			(format nil "for (uint32_t i = 0; i < ~a; i++){tmp->elems[i] = x->elems[i];~%~
                                     ~16Tx->elems[i]->count++;}"
				size)
		      (format nil "for (uint32_t i = 0; i < ~a; i++){tmp->elems[i] = x->elems[i];}"
				size))))
  (format nil "~a_t ~a(~a_t x){~%~8T~a_t tmp = new_~a();~%~8T~
               tmp->count = 1;~
	       ~%~8T~a;~%~8T return tmp;}"   
	  type-name-root copy-name type-name-root type-name-root type-name-root copy-instr)))

(defun make-array-update-header (update-name type-name-root ir-range)
  (let* ((range-type-info (get-c-type-info ir-range))
	 (range-type-name (if range-type-info (tname range-type-info) (ir-type-id ir-range))))
    (format nil "extern ~a_t ~a(~a_t x, uint32_t i, ~a_t v);" type-name-root update-name  type-name-root range-type-name)))

(defun make-array-update-defn (update-name type-name-root ir-range)
  (let* ((range-type-info (get-c-type-info ir-range))
	 (range-type-name (if range-type-info (tname range-type-info) (ir-type-id ir-range))))
    (if (ir-reference-type? ir-range)
	(format nil "~a_t ~a(~a_t x, uint32_t i, ~a_t v){~%~8T ~a_t y;~%~8T if (x->count == 1){y = x;}~%~16T else {y = copy_~a(x);};~%~8T~
                     ~a_t * yelems = y->elems;~%~8T~
                     if (yelems[i] != NULL){release_~a(yelems[i]);};~%~8T yelems[i] = v; if (v != NULL){v->count++;}~%~8T return y;}"
		type-name-root update-name type-name-root range-type-name type-name-root type-name-root range-type-name range-type-name)
    (format nil "~a_t ~a(~a_t x, uint32_t i, ~a_t v){~%~8T~a_t y; ~% if (x->count == 1){y = x;}~%~16T else {y = copy_~a(x);}~%~8T~
                    y->elems[i] = v;~%~8T~
                    return y;}"
	    type-name-root update-name type-name-root range-type-name type-name-root type-name-root))))


(defmethod add-c-type-definition ((ir2c-type ir-recordtype) &optional tname)
  (with-slots (ir-field-types) ir2c-type
	      (let* ((c-type-info (get-c-type-info ir2c-type))
		     (c-type-name (when c-type-info (tname c-type-info))))
		(or c-type-name
		    (let* ((c-field-types (loop for ft in ir-field-types
					       collect (add-c-type-definition (ir-ftype ft))))
			   (type-name-root (or tname (format nil "record_~a" (length *c-type-info-table*))))
			   (c-field-decls (loop for cft in c-field-types
						as ft in ir-field-types
						collect (format nil "~a_t ~a" cft (ir-id ft))))
			   (type-defn (format nil "struct ~a_s { uint32_t count; ~{~% ~a;~}};~%typedef struct ~a_s * ~a_t;"
					      type-name-root c-field-decls type-name-root type-name-root)));(break "add-c-type-definition")
		      (let* ((new-info (make-record-new-info type-name-root))
			     (release-info (make-record-release-info type-name-root ir-field-types c-field-types))
			     (copy-info (make-record-copy-info type-name-root ir-field-types c-field-types))
			     (update-info (loop for cft in c-field-types
						as ft in ir-field-types
						collect (make-record-field-update-info type-name-root ft cft))))
			    (push (mk-c-type-info ir2c-type type-name-root type-defn new-info release-info copy-info update-info)
				  *c-type-info-table*)
			    type-name-root))))))

(defmethod add-c-type-definition ((ir2c-type ir-adt-recordtype) &optional tname)
  (with-slots (ir-field-types ir-constructors) ir2c-type
	      (let* ((c-type-info (get-c-type-info ir2c-type))
		     (c-type-name (when c-type-info (tname c-type-info))))
		(or c-type-name
		    (let* ((c-field-types (loop for ft in ir-field-types
					       collect (add-c-type-definition (ir-ftype ft))))
			   (type-name-root (or tname (format nil "record_~a" (length *c-type-info-table*))))
			   (c-field-decls (loop for cft in c-field-types
						as ft in ir-field-types
						collect (format nil "~a_t ~a" cft (ir-id ft))))
			   (type-defn (format nil "struct ~a_s { uint32_t count; ~{~% ~a;~}};~%typedef struct ~a_s * ~a_t;"
					      type-name-root c-field-decls type-name-root type-name-root)));(break "add-c-type-definition")
		      (let* ((new-info (make-record-new-info type-name-root))
			     (release-info (make-adt-record-release-info type-name-root ir-field-types c-field-types ir-constructors))
			     (copy-info (make-record-copy-info type-name-root ir-field-types c-field-types))
			     (update-info (loop for cft in c-field-types
						as ft in ir-field-types
						collect (make-record-field-update-info type-name-root ft cft))))
			    (push (mk-c-type-info ir2c-type type-name-root type-defn new-info release-info copy-info update-info)
				  *c-type-info-table*)
			    type-name-root))))))



(defun make-record-new-info (type-name-root)
    (let* ((new-name (intern (format nil "new_~a" type-name-root)))
	   (new-header (format nil "extern ~a_t new_~a(void);" type-name-root type-name-root))
	   (new-defn   (format nil "~a_t new_~a(void){~%~a_t tmp;~%tmp = (~a_t) malloc(sizeof(struct ~a_s));~%~8Ttmp->count = 1;~%~8Treturn tmp;}"
			       type-name-root type-name-root type-name-root type-name-root type-name-root)))
      (mk-c-defn-info new-name new-header new-defn)))

(defun make-adt-record-release-info (type-name-root ir-field-types c-field-types constructors)
  (let* ((release-name (intern (format nil "release_~a" type-name-root)))
	 (release-header (format nil "extern void release_~a(~a_t x);" type-name-root type-name-root))
	 (release-defn (let ((release-fields (loop for constructor in constructors
						   as index from 0
						   when (cdr constructor)
						   collect (format nil "case ~a:  release_~a((~a_t) x); break"
								   index
								   (car constructor)
								   (car constructor)))))
						   
			 (format nil "void release_~a(~a_t x){~%switch (x->~a_index) {~{~%~a;~}~%}}"
				 type-name-root type-name-root type-name-root release-fields))))
    (mk-c-defn-info release-name release-header release-defn)))

(defun make-record-release-info (type-name-root ir-field-types c-field-types)
  (let* ((release-name (intern (format nil "release_~a" type-name-root)))
	 (release-header (format nil "extern void release_~a(~a_t x);" type-name-root type-name-root))
	 (release-defn (let ((release-fields (loop for ft in ir-field-types
						   as cft in c-field-types
						   when (ir-reference-type? (ir-ftype ft))
						   collect (format nil "release_~a(x->~a)" cft (ir-id ft)))))
						   
			 (format nil "void release_~a(~a_t x){~%x->count--;~%if (x->count <= 0){~{~%~a;~}~%free(x);}}"
				 type-name-root type-name-root release-fields))))
    (mk-c-defn-info release-name release-header release-defn)))

(defun make-record-copy-info (type-name-root ir-field-types c-field-types)
  (let* ((copy-name (intern (format nil "copy_~a" type-name-root)))
	 (copy-header (format nil "extern ~a_t ~a(~a_t x);" type-name-root copy-name type-name-root))
	 (copy-defn (make-record-copy-defn type-name-root ir-field-types c-field-types)))
    (mk-c-defn-info copy-name copy-header copy-defn)))

(defun make-record-copy-defn (type-name-root ir-field-types c-field-types)
  (let ((copy-field-instrs
	 (loop for ft in ir-field-types
	       as cft in c-field-types
	       collect (if (ir-reference-type? (ir-ftype ft))
			   (format nil "~%y->~a = x->~a;~%if (y->~a != NULL){y->~a->count++;}"
					;type-name-root
				   (ir-id ft)
					;type-name-root
				   (ir-id ft)
					;type-name-root
				   (ir-id ft)
					;type-name-root
				   (ir-id ft))
			 (format nil "~%y->~a = x->~a"
				    (ir-id ft)  (ir-id ft))))))
    (format nil "~a_t copy_~a(~a_t x){~%~8T~a_t y = new_~a();~%~8T~{~a;~}~%y->count = 1;~%~8Treturn y;}"
	    type-name-root type-name-root type-name-root type-name-root type-name-root copy-field-instrs)))


(defun make-record-field-update-info (type-name-root ir-field-type c-field-type)
  (let* ((update-name (intern (format nil "update_~a_~a" type-name-root (ir-id ir-field-type))))
	 (update-header (format nil "extern ~a_t ~a(~a_t x, ~a_t v);" type-name-root update-name type-name-root c-field-type))
	 (update-defn (make-record-field-update-defn update-name type-name-root ir-field-type c-field-type)))
    (mk-c-defn-info update-name update-header update-defn)))

(defun make-record-field-update-defn (update-name type-name-root ir-field-type c-field-type)
  (let ((fname (ir-id ir-field-type))
	(ftype (ir-ftype ir-field-type)))
    (if (ir-reference-type? ftype)
	(format nil "~a_t ~a(~a_t x, ~a_t v){~%~8T~a_t y;~%~8Tif (x->count == 1){y = x; if (x->~a != NULL){release_~a(x->~a);};}~%~16T~
                     else {y = copy_~a(x); y->~a->count--;};~%~8T~
                     y->~a = v;~%~8Tif (v != NULL){v->count++;};~%~8Treturn y;}"
		type-name-root update-name type-name-root c-field-type type-name-root fname c-field-type
		fname type-name-root fname fname)
      (format nil "~a_t ~a(~a_t x, ~a_t v){~%~8T~a_t y;~%~8Tif (x->count == 1){y = x;}~%~16T~
                     else {y = copy_~a(x);};~%~
                     ~8Ty->~a = v;~%~8Treturn y;}"
		type-name-root update-name type-name-root c-field-type type-name-root 
		type-name-root fname))))

;;equality method for ir-types
(defun ir2c-tequal (texpr1 texpr2)
  ;(format t "~%ir2c-tequal")
  ;(format t "~%texpr1: ~a" (print-ir texpr1))
   ; (format t "~%texpr2: ~a" (print-ir texpr2))
  (ir2c-tequal* texpr1 texpr2))

(defmethod ir2c-tequal* ((texpr1 ir-recordtype)(texpr2 ir-recordtype))
  (with-slots ((ir-ftypes1 ir-field-types)) texpr1
	      (with-slots ((ir-ftypes2 ir-field-types)) texpr2
			  (ir2c-tequal* ir-ftypes1 ir-ftypes2))))

(defmethod ir2c-tequal* ((texpr1 list)(texpr2 list))
  (cond ((consp texpr1)
	 (and (consp texpr2)
	      (ir2c-tequal* (car texpr1)(car texpr2))
	      (ir2c-tequal* (cdr texpr1)(cdr texpr2))))
	(t (not (consp texpr2)))))

(defmethod ir2c-tequal* ((texpr1 ir-fieldtype)(texpr2 ir-fieldtype))
  (with-slots ((ir-id1 ir-id)(ir-ftype1 ir-ftype)) texpr1
	      (with-slots ((ir-id2 ir-id)(ir-ftype2 ir-ftype)) texpr2
			  (and (eq ir-id1 ir-id2)
			       (ir2c-tequal* ir-ftype1 ir-ftype2)))))

(defmethod ir2c-tequal* ((texpr1 ir-funtype)(texpr2 ir-funtype))
  (with-slots ((ir-dom1 ir-domain)(ir-ran1 ir-range)) texpr1
	      (with-slots ((ir-dom2 ir-domain)(ir-ran2 ir-range)) texpr2
			  (and (ir2c-tequal* ir-dom1 ir-dom2)
			       (ir2c-tequal* ir-ran1 ir-ran2)))))

(defmethod ir2c-tequal* ((texpr1 ir-arraytype)(texpr2 ir-arraytype))
  (with-slots ((size1 size)(elemtype1 elemtype)) texpr1
	      (with-slots ((size2 size)(elemtype2 elemtype)) texpr2
			  (and (eql size1 size2)
			       (ir2c-tequal* elemtype1 elemtype2)))))

(defmethod ir2c-tequal* ((texpr1 ir-subrange )(texpr2 ir-subrange))
  (equal (ir2c-type texpr1)(ir2c-type texpr2)))

(defmethod ir2c-tequal* ((texpr1 ir-typename)(texpr2 ir-typename))
  (with-slots ((id1 ir-type-id)(tdef1 ir-type-defn)) texpr1
	      (with-slots ((id2 ir-type-id)(tdef2 ir-type-defn)) texpr2
			  ;(and (eq id1 id2))
			  (ir2c-tequal* tdef1 tdef2))))

(defmethod ir2c-tequal* ((texpr1 ir-typename)(texpr2 t))
  (with-slots ((id1 ir-type-id)(tdef1 ir-type-defn)) texpr1
	      (ir2c-tequal* tdef1 texpr2)))

(defmethod ir2c-tequal* ((texpr1 t)(texpr2 ir-typename))
  (with-slots ((id2 ir-type-id)(tdef2 ir-type-defn)) texpr2
	      (ir2c-tequal* texpr1 tdef2)))



(defmethod ir2c-tequal* ((texpr1 t)(texpr2 t))
  (eq texpr1 texpr2));;Since the base case

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun pvs2c-decl (decl)
  (let ((saved-c-type-info-table *c-type-info-table*))
    (handler-case
     (pvs2c-decl* decl)
     (pvs2c-error (condition) (format t "~%closures not handled")
		  (setq *c-type-info-table* saved-c-type-info-table)))))
  
(defmethod pvs2c-decl* ((decl type-eq-decl))
  (let ((typename (pvs2ir-decl decl)))
    ;(break "type-eq-decl")
    (add-c-type-definition (ir2c-type (ir-type-defn typename))(ir-type-id typename))))

(defmethod pvs2c-decl* ((decl type-decl)) ;;has to be an adt-type-decl
  (pvs2ir-adt-decl decl))
  

;;conversion for a definition
(defmethod pvs2c-decl* ((decl const-decl))
  (pvs2ir-decl decl)
  (let ((ir (ir (eval-info decl))));(break "pvs2c-decl*/const-decl")
    (ir2c-decl* ir decl)))

(defun make-c-defn-info (ir decl)
  (with-slots (ir-function-name ir-defn) ir
    (format t "~%ir-defn~% =~a" (print-ir ir-defn))
    (when ir-defn
      (let* ((post-ir (preprocess-ir ir-defn))
	     (ir-args (when (ir-lambda? post-ir)
			(ir-vartypes post-ir)))
	     (ir-result-type (if (ir-lambda? post-ir)
				 (ir-rangetype post-ir) ;(pvs2ir-type (range (find-supertype (type decl))))
			      (pvs2ir-type (type decl))))
	     (c-result-type (add-c-type-definition (ir2c-type ir-result-type)))
	     (c-args (loop for arg in ir-args
			   collect (format nil "~a_t ~a"
					   (add-c-type-definition (ir2c-type (ir-vtype arg)))
					   (ir-name arg))))
	     (c-args-string (if (consp c-args)
				(format nil "~{~a~^, ~}" c-args)
			      (format nil "void")))
	     (c-header (format nil "extern ~a_t ~a(~a);" c-result-type ir-function-name c-args-string))
	     (ir-body (if (ir-lambda? post-ir)
			 (ir-body post-ir)
			post-ir))
	     (c-body (print2c (ir2c ir-body ir-result-type)))
	     (c-defn (format nil "~a_t ~a(~a){~%~8T~a_t result;~%~a~%~8Treturn result;~%}"
			     c-result-type ir-function-name c-args-string
			     c-result-type
			     c-body)))
	(format t "~%After preprocessing = ~%~a" (print-ir post-ir))
	(format t "~%Generates C definition = ~%~a" c-defn)
	(mk-c-defn-info ir-function-name c-header c-defn)))))


(defmethod ir2c-decl* ((ir ir-accessor-defn) decl)
  (let ((cdefn (make-c-defn-info ir decl))
	(udefn (make-c-defn-info (ir-update-defn ir) decl)))
    (setf (cdefn (eval-info decl)) cdefn
	  (update-cdefn (eval-info decl)) udefn)
    (op-name cdefn)))

(defmethod ir2c-decl* ((ir ir-defn) decl)
  (let ((cdefn (make-c-defn-info ir decl)))
    (setf (cdefn (eval-info decl)) cdefn)
    (op-name cdefn)))

(defmethod ir2c-decl* ((ir ir-constructor-defn) decl)
  (with-slots (ir-constructor-type) ir
	      (with-slots (ir-type-id ir-type-defn) ir-constructor-type
			  (add-c-type-definition (ir2c-type ir-type-defn) ir-type-id))
	      (call-next-method)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;printing out the C code in a block-structured manner
;;the translated code is a list of instructions, where each
;;instruction is either a regular C instruction or an if-instr

(defvar *c-scope-string* "~8T")
(defun print2c (c-instrs)
  (cond ((consp c-instrs)
	 (cond ((if-instr? (car c-instrs))
		(with-slots (if-cond then-instr else-instr) (car c-instrs)
			    (let* ((then-part
				    (let ((*c-scope-string*
					   (format nil "~a~a" "~~8T" *c-scope-string*)))
				      (print2c then-instr)))
				   (else-part
				    (let ((*c-scope-string*
					   (format nil "~a~a" "~~8T" *c-scope-string*)))
				      (print2c else-instr)))
				
				   (if-string (format nil "~aif (~a){~a~%~a} else {~%~a~%~a}"
						      *c-scope-string*
						      if-cond
						      *c-scope-string*
						      then-part
						      *c-scope-string*
						      else-part)))
			      (format nil "~a;~%~a" (format nil if-string)
				      (print2c (cdr c-instrs))))))
	       ((for-instr? (car c-instrs))
		(let* ((for-body (for-body (car c-instrs)))
		       (for-index (for-index (car c-instrs)))
		       (c-for-body (let ((*c-scope-string*
					  (format nil "~a~a" "~~8T" *c-scope-string*)))
				     (print2c for-body))))
		  (format nil (format nil "~afor (~a){~%~a~a};~%~a"
				      *c-scope-string* for-index
				      c-for-body *c-scope-string*
				      (print2c (cdr c-instrs))))))
	       (t (format nil (format nil "~a~a;~%~a" *c-scope-string* (car c-instrs)
				      (print2c (cdr c-instrs)))))))
	(t (format nil ""))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;print the header file from the information in *c-type-info-table*
;;If the type has a PVS definition, the type-info is saved with this declaration.
;;Otherwise, the type information is generated for the type expression in the global.

(defun print-header-file (theory)
  (let* ((file-string (format nil "~a_c.h" (id theory))))
    (with-open-file (output file-string :direction :output
			    :if-exists :supersede
			    :if-does-not-exist :create)
		    (format output "//Code generated using pvs2ir2c")
		    (format output "~%~%#include<stdio.h>")
		    (format output "~%~%#include<stdlib.h>")
		    (format output "~%~%#include<inttypes.h>")
		    (format output "~%~%#include<stdbool.h>")		    
		    (format output "~%~%#include<gmp.h>")
		    (format output "~%~%typedef bool bool_t;")
		    (print-type-info-headers-to-file output *c-type-info-table*)
		    (loop for decl in (theory theory)
		     	  when (and (const-decl? decl)(eval-info decl)(cdefn (eval-info decl)))
			  do (print-header-decl decl output))
		    (id theory))))

(defun print-header-decl (decl output)
  (let ((einfo (eval-info decl)))
    (when (accessor-eval-info? einfo)
      (format output "~%~%~a" (op-header (update-cdefn (eval-info decl)))))
    (format output "~%~%~a" (op-header (cdefn (eval-info decl))))))

(defun print-type-info-headers-to-file (output type-info-stack)
  (cond ((consp type-info-stack)
	 (print-type-info-headers-to-file output (cdr type-info-stack))
	 (print-type-defn-headers (car type-info-stack) output))
	(t nil)))

(defmethod print-type-defn-headers ((type-info simple-c-type-info) output)
  (format output "~%~%~a~%~%"
	  (tdefn type-info)))

(defmethod print-type-defn-headers ((type-info c-type-info) output)
  (format output "~%~%~a~%~%~a~%~%~a~%~%~a~%~%"
	  (tdefn type-info)
	  (op-header (new-info type-info))
	  (op-header (release-info type-info))
	  (op-header (copy-info type-info)))
  (loop for t-info in (update-info type-info)
	do (format output "~a~%~%" (op-header t-info))))

(defun print-type-info-defns-to-file (output type-info-stack)
  (cond ((consp type-info-stack)
	 (print-type-info-defns-to-file output (cdr type-info-stack))
	 (print-type-defns (car type-info-stack) output))
	(t nil)))

(defmethod print-type-defns ((type-info simple-c-type-info) output)
  nil); do nothing

(defmethod print-type-defns ((type-info c-type-info) output)
  (format output "~%~%~%~a~%~%~a~%~%~a~%~%"
	  (op-defn (new-info type-info))
	  (op-defn (release-info type-info))
	  (op-defn (copy-info type-info)))
  (loop for t-info in (update-info type-info)
	do (format output "~a~%~%" (op-defn t-info))))


(defun print-body-file (theory)
  (let* ((file-string (format nil "~a_c.c" (id theory))))
    (with-open-file (output file-string :direction :output
			    :if-exists :supersede
			    :if-does-not-exist :create)
		    (format output "//Code generated using pvs2ir2c")
		    (format output "~%#include \"~a_c.h\"" (id theory))
		    (print-type-info-defns-to-file output *c-type-info-table*)
		    (loop for decl in (theory  theory)
			  do (let ((einfo (and (const-decl? decl)(eval-info decl))))
			       (when (and einfo (cdefn (eval-info decl)))
				 (when (accessor-eval-info? einfo)
				   (format output "~%~%~a" (op-defn (update-cdefn (eval-info decl)))))
				 (format output "~%~%~a" (op-defn (cdefn (eval-info decl)))))))
		    (id theory))))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun adt-operation? (decl)
  (typep decl
	 '(or adt-constructor-decl adt-recognizer-decl
	      adt-accessor-decl adt-def-decl)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;pvs2c-theory computes definitions for the entire theory while
;;stacking type definitions in *c-type-info-table*

(defun adt-type-decl? (decl)
  (and (type-decl? decl)
       (adt-type-name? (type-value decl))))

(defun pvs2c-theory (theory)
  (let* ((theory (or (get-theory theory) *current-theory*))
	 (*ir-type-info-table* nil)
	 (*c-type-info-table* nil))
    (loop for decl in (theory theory)
	  when (or (and (const-decl? decl)(or (adt-operation? decl)(def-axiom decl)))
		   (type-eq-decl? decl)(adt-type-decl? decl))
	      do (pvs2c-decl decl))
    (print-header-file theory)
    (print-body-file theory)))

    
		
		    

	  
