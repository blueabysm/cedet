;;; semanticdb.el --- Semantic token database manager

;;; Copyright (C) 2000 Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: tags
;; X-RCS: $Id: semanticdb.el,v 1.5 2000-12-12 02:38:11 zappo Exp $

;; This file is not part of GNU Emacs.

;; Semanticdb is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This software is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; Maintain a database of tags for a group of files and enable
;; queries into the database.
;;
;; By default, assume one database per directory.
;;
;; Eventually, use EDE to create databases on a per target basis, and
;; then use target dependencies to have them reference each other.

(require 'eieio-base)

;;; Variables:
(defcustom semanticdb-default-file-name "semantic.cache"
  "*File name of the semantic token cache."
  :group 'semantic
  :type 'string)

(defcustom semanticdb-save-database-hooks nil
  "*Hooks run after a database is saved.
Each function is called with one argument, the object representing
the database recently written."
  :group 'semantic
  :type 'hook)

(defvar semanticdb-database-list nil
  "List of all active databases.")

(defvar semanticdb-semantic-init-hook-overload nil
  "Semantic init hook overload.
Tools wanting to specify the file names of the semantic database
use this.")

(defvar semanticdb-current-database nil
  "For a given buffer, this is the currently active database.")
(make-variable-buffer-local 'semanticdb-current-database)

(defvar semanticdb-current-table nil
  "For a given buffer, this is the currently active database table.")
(make-variable-buffer-local 'semanticdb-current-table)

;;; Classes:
(defclass semanticdb-project-database (eieio-persistent
				       eieio-instance-tracker)
  ((tracking-symbol :initform semanticdb-database-list)
   (file-header-line :initform ";; SEMANTICDB Tags save file")
   (tables :initarg :tables
	   :type list
	   :documentation "List of `semantic-db-table' objects."))
  "Database of file tables.")

(defclass semanticdb-table ()
  ((file :initarg :file
	 :documentation "File name relative to the parent database.
This is for the file whose tags are stored in this TABLE object.")
   (pointmax :initarg :pointmax
	     :initform nil
	     :documentation "Size of buffer when written to disk.
Checked on retrieval to make sure the file is the same.")
   (tokens :initarg :tokens
	   :documentation "The tokens belonging to this table."))
  "A single table of tokens belonging to a given file.")

;;; Code:
(defun semanticdb-create-database (filename)
  "Create a semantic database in FILENAME and return it.
If FILENAME has already been loaded, return it.
If FILENAME exists, then load that database, and return it.
If FILENAME doesn't exist, create a new one."
  (if (file-exists-p filename)
      (or (semanticdb-file-loaded-p filename)
	  (semanticdb-load-database filename))
    (semanticdb-project-database (file-name-nondirectory filename)
				 :file filename
				 :tables nil)))

(defun semanticdb-get-database (filename)
  "Get a database for FILENAME.
If one isn't found, create one."
  (or (eieio-instance-tracker-find filename 'file 'semanticdb-database-list)
      (semanticdb-create-database filename)))

(defun semanticdb-load-database (filename)
  "Load the database FILENAME."
  (eieio-persistent-read filename))

(defun semanticdb-file-loaded-p (filename)
  "Return the project belonging to FILENAME if it was already loaded."
  (object-assoc filename 'file semanticdb-database-list))

(defmethod semanticdb-file-table ((obj semanticdb-project-database) filename)
  "From OBJ, return FILENAMEs associated table object."
  (object-assoc (eieio-persistent-path-relative obj filename)
		'file (oref obj tables)))

(defun semanticdb-save-db (&optional DB)
  "Write out the database DB to its file.
If DB is not specified, then use the current database."
  (condition-case nil
      (progn
	(eieio-persistent-save (or DB semanticdb-current-database))
	(run-hooks 'semanticdb-save-database-hooks DB))
    (error nil)))

(defun semanticdb-save-all-db ()
  "Save all semantic token databases."
  (message "Saving token summaries...")
  (mapcar 'semanticdb-save-db semanticdb-database-list)
  (message "Saving token summaries...done"))

(defmethod object-write ((obj semanticdb-table))
  "When writing a table, we have to make sure we deoverlay it first.
Restore the overlays after writting.
Argument OBJ is the object to write."
  (let ((b (get-file-buffer (oref obj file))))
    (save-excursion
      (if b (progn (set-buffer b) (semantic-deoverlay-cache)
		   (oset obj pointmax (point-max)))))
    (call-next-method)
    (save-excursion
      (if b (progn (set-buffer b) (semantic-overlay-cache))))
    ))

;;; hooks and Hats:
(defun semanticdb-semantic-init-hook-fcn ()
  "Function saved in `find-file-hooks'.
Sets up the semanticdb environment."
  (let ((cdb nil)
	(ctbl nil))
    (if (not (and semanticdb-semantic-init-hook-overload
		  (setq cdb (run-hooks semanticdb-semantic-init-hook-overload))))
	(setq cdb
	      (semanticdb-get-database
	       (concat (file-name-directory (buffer-file-name))
		       semanticdb-default-file-name))))
    (setq semanticdb-current-database cdb)
    (setq ctbl (semanticdb-file-table cdb (buffer-file-name)))
    (unless ctbl
      (setq ctbl
 	    (semanticdb-table
	     (eieio-persistent-path-relative
	      semanticdb-current-database (buffer-file-name))
	     :file (eieio-persistent-path-relative
		    semanticdb-current-database (buffer-file-name))
	     ))
      (object-add-to-list semanticdb-current-database
			  'tables
			  ctbl
			  t))
    (setq semanticdb-current-table ctbl)
    (if (or (not (slot-boundp ctbl 'tokens)) (not (oref ctbl tokens))
	    (/= (or (oref ctbl pointmax) 0) (point-max))
	    )
	(progn
	  (semantic-clear-toplevel-cache)
	  (condition-case nil
	      (semantic-bovinate-toplevel t)
	    (quit (message "semanticdb: Semantic Token generation halted."))
	    (error (error "Semanticdb: bovination failed at startup"))))
      (semantic-set-toplevel-bovine-cache  (oref ctbl tokens))
      (semantic-overlay-cache))
    ))

(defun semanticdb-post-bovination ()
  "Function run after a bovination."
  (if semanticdb-current-table
      (oset semanticdb-current-table tokens semantic-toplevel-bovine-cache)))

(defun semanticdb-kill-hook ()
  "Function run when a buffer is killed.
If there is a semantic cache, slurp out the overlays, an store
it in our database.  If that buffer has not cache, ignore it, we'll
handle it later if need be."
  (if (and semantic-toplevel-bovine-table
	   semantic-toplevel-bovine-cache)
      (progn
	(oset semanticdb-current-table pointmax (point-max))
	(condition-case nil
	    (semantic-deoverlay-cache)
	  ;; If this messes up, just clear the system
	  (error
	   (semantic-clear-toplevel-cache)
	   (message "semanticdb: Failed to deoverlay token cache."))))
    ))

(defun semanticdb-kill-emacs-hook ()
  "Function called when Emacs is killed.
Save all the databases."
  (semanticdb-save-all-db))

;;; Start/Stop database use
;;
(defvar semanticdb-hooks
  '((semanticdb-semantic-init-hook-fcn semantic-init-hooks)
    (semanticdb-post-bovination semantic-after-toplevel-bovinate-hook)
    (semanticdb-kill-hook kill-buffer-hook)
    (semanticdb-kill-emacs-hook kill-emacs-hook)
    )
  "List of hooks and values to add/remove when configuring semanticdb.")

(defun semanticdb-minor-mode-p ()
  "Return non-nil if `semanticdb-minor-mode' is active."
  (member (car (car semanticdb-hooks))
	  (symbol-value (car (cdr (car semanticdb-hooks))))))

(defun global-semanticdb-minor-mode (&optional arg)
  "Toggle the use of `semanticdb-minor-mode'.
If ARG is positive, enable, if it is negative, disable.
If ARG is nil, then toggle."
  (interactive "P")
  (if (not arg)
      (if (semanticdb-minor-mode-p)
	  (setq arg -1)
	(setq arg 1)))
  (let ((fn 'add-hook)
	(h semanticdb-hooks))
    (if (< arg 0)
	(setq fn 'remove-hook))
    ;(message "ARG = %d" arg)
    (while h
      (funcall fn (car (cdr (car h))) (car (car h)))
      (setq h (cdr h)))))

;;; Utilities
;;
;; Line all the semantic-util 'find-nonterminal...' type functions, but
;; trans file across the database.
(defun semanticdb-find-nonterminal-by-name (name &optional database)
  "Find a nonterminal with name NAME in our databases.
Search for it in DATABASE if provided, otherwise search a range
of databases."
  
  )

(defun semanticdb-file-stream (file)
  "Return a list of tokens belonging to FILE.
If file has database tokens available in the database, return them.
If file does not have tokens available, then load the file, and create them."
  (let* ((fo (semanticdb-get-database (concat (file-name-directory file)
					      semanticdb-default-file-name)))
	 (to nil))
    (if fo (setq to (semanticdb-file-table fo file)))
    (if to
	(oref to tokens) ;; get them.
      ;; We must load the file.
      (save-excursion
	(set-buffer (find-file-noselect file))
	;; Find file should automatically do this for us.
	(if semanticdb-current-table
	    (oref semanticdb-current-table tokens)
	  ;; if not, just do it.
	  (semantic-bovinate-toplevel t))))
    ))

(provide 'semanticdb)

;;; semanticdb.el ends here
