(in-package :cl-mongo)

#|
  Document is a collection of key/value pairs
|#

(defun make-elements (size)
  (make-hash-table :test #'equal :size size))

(defclass document()
  ((elements  :initarg :elements :accessor elements)
   (_local_id :initarg :local    :reader _local)
   (_id       :initarg :oid      :reader _id))
  (:default-initargs
   :local t
   :oid (make-bson-oid))
  (:documentation "document
Document class. A document consists of key/value pairs stored in a internal hash table plus 
an internally generated unique id.   
Accessors are : 'elements' which returns the internal hash table;
'_id' which  returns the unique id and '_local_id' which if true means that 
the document was generated by the client (as opposed to having been read from the server)."))

(defun make-document ( &key (oid nil) (size 40))
  "Constructor.  key ':oid' is a user supplied unique id. An internal id will be generated if none 
   is supplied."
  (if oid
      (make-instance 'document :oid oid :local nil :elements (make-elements size))
      (make-instance 'document :elements (make-elements size))))

(defgeneric add-element ( key value document) 
  ( :documentation "add element with key and value to a document" ) )

(defmethod add-element (key value document)
  document)

(defmethod add-element ( (key string) value (document document) )
  (setf (gethash key (elements document)) value)
  (call-next-method))

(defgeneric get-element ( key document) 
  ( :documentation "Get an element identified by key from the document." ) )

(defmethod get-element ( (key string) (document (eql nil) ) )
  (values nil nil))

(defmethod get-element ( (key string) (document document) ) 
  (gethash key (elements document)))

(defgeneric rm-element (key document) 
  ( :documentation "Remove element identified by key from a document" ) )

(defmethod rm-element ( (key string) (document document) ) 
  (remhash key (elements document)))

(defgeneric get-id (id) )

(defmethod get-id ( (id t) )
    id)

(defmethod get-id ( (id bson-oid) )
    (id id))

(defun doc-id (doc)
  "return the unique document id"
  (get-id (_id doc)))

;;
;; When the to-hash-able finalizer is used, embedded docs/tables in the response aren't converted
;; to hash tables but to documents. When print-hash is used we want to see hash table like output
;; so that's what this tries to do..
;;
(defun print-hash (ht stream &key (max (hash-table-count ht)))
  (labels ((prdocs (docs) 
	     (format stream "~1,1T[")
	     (block print-array
	       (let ((counter 0))
		 (dolist (doc docs)
		   (incf counter)
		   (if (typep doc 'document)
		       (print-hash (elements doc) stream :max max)
		       (format stream "~A," doc))
		   (when (> counter 100)
		     (progn
		       (format stream "[....](~A elements left)" (- (length docs) 100))
		       (return-from print-array nil))))))
	     (format stream "]~%"))
	   (vpr (v)
	     (cond ( (typep v 'cons)     (prdocs v)        )
		   ( (typep v 'document) (prdocs (list v)) )
		   (  t                  (format stream "~A~%" v)))))
    (format stream "~%~3,8T{~%") 
    (with-hash-table-iterator (iterator ht)
      (dotimes (repeat max)
	(multiple-value-bind (exists-p key value) (iterator)
	  (if exists-p 
	      (progn 
		(format stream "~3,8T~A -> " key) 
		(vpr value))))))
    (when (< max (hash-table-count ht)) (format stream "~3,8T[..............]~%"))
    (format stream "~3,8T}~%")))

(defun hash-keys (ht)
  (let ((lst))
    (with-hash-table-iterator (iterator ht)
      (dotimes (repeat (hash-table-count ht))
	(multiple-value-bind (exists-p key value) (iterator)
	  (if exists-p (push key lst)))))
    (nreverse lst)))


;
; suppress the printing of the object id if the objectis locally generated
;

(defmethod describe-object ((document document) stream)
  (format stream "~%{  ~S ~%" (type-of document) ) 
  (unless (slot-boundp  document '_id)       (format stream "  _id not set"))
  (unless (slot-boundp  document '_local_id) (format stream "  _local_id not set"))
  (when (and (slot-boundp  document '_local_id) (slot-boundp  document '_id) )
    (unless (_local document) (format stream "  _id : ~A~%" (_id document))))
  (if (slot-boundp document 'elements)
      (print-hash (elements document) stream)
      "no elements set..")
  (format stream "}~%")) 

(defmethod print-object.2 ((document document) stream)
  (format stream "<~S> : { ~%" (type-of document) ) 
  (when (and (slot-boundp  document '_local_id) (slot-boundp  document '_id) )
    (unless (_local document) (format stream "~3,8T_id : ~A~%" (_id document))))
  (if (slot-boundp document 'elements)
      (progn
	(format stream "~3,8Telements : ~A" (hash-table-count (elements document) ))
	(print-hash (elements document) stream :max 20))
      "no elements set..")
  (format stream "}~%"))

(defmethod print-object.1 ((document document) stream)
  (format stream "<~S> : { ~%" (type-of document) ) 
  (when (and (slot-boundp  document '_local_id) (slot-boundp  document '_id) )
    (unless (_local document) (format stream "~3,8T_id : ~A~%" (_id document))))
  (if (slot-boundp document 'elements)
	(format stream "~3,8Telements : ~A" (hash-table-count (elements document))))
  (format stream "}~%"))

(defmethod print-object ((document document) stream)
  (let ((str (with-output-to-string (stream) (print-object.1 document stream))))
    (format stream "~A~%" str)))


(defun ht->document (ht) 
  "Convert a hash-table to a document."
  (multiple-value-bind (oid oid-supplied) (gethash "_id" ht)
    (let ((doc (make-document :oid (if oid-supplied oid nil))))
      (when oid-supplied (remhash "_id" ht))
      (with-hash-table-iterator (iterator ht)
	(dotimes (repeat (hash-table-count ht))
	  (multiple-value-bind (exists-p key value) (iterator)
	    (if exists-p (add-element key value doc)))))
      doc)))
;;------------


(defun ht->document.1 (ht) 
  (multiple-value-bind (oid oid-supplied) (gethash "_id" ht)
      (if oid-supplied
	  (progn 
	    (remhash "_id" ht)
	    (make-instance 'document :oid oid :local nil :elements ht))
	  (make-instance 'document :elements ht))))

;;--------------------

(defun mapdoc (fn document)
  (let ((lst ())
	(ht (elements document)))
    (with-hash-table-iterator (iterator ht)
      (dotimes (repeat (hash-table-count ht))
	(multiple-value-bind (exists-p key value) (iterator)
	  (if exists-p (push (funcall fn key value) lst)))))
    (nreverse lst)))
	       
(defgeneric doc-elements (document) )

(defmethod doc-elements ( (document hash-table) )
  (let ((lst ()))
    (with-hash-table-iterator (iterator document)
      (dotimes (repeat (hash-table-count document))
	(multiple-value-bind (exists-p key value) (iterator)
	  (if exists-p (push key lst)))))
    lst))

(defmethod doc-elements ( (document document) )
  (doc-elements (elements document)))

;;----------------------------

(defun ht-test (size)
  (let ((ht (make-hash-table :test #'equal)))
    (dotimes (var size)
      (setf (gethash var ht) (format nil "value stored : ~A~%" var)))
    ht))
