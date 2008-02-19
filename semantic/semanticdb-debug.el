;;; semanticdb-debug.el --- Extra level debugging routines

;; Copyright (C) 2008 Eric M. Ludlam

;; Author: Eric M. Ludlam <eric@siege-engine.com>
;; X-RCS: $Id: semanticdb-debug.el,v 1.2 2008-02-12 17:35:50 zappo Exp $

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Various routines for debugging SemanticDB issues, or viewing 
;; semanticdb state.

(require 'semanticdb)

;;; Code:
;;
;;;###autoload
(defun semanticdb-dump-all-table-summary ()
  "Dump a list of all databases in Emacs memory."
  (interactive)
  (require 'semantic-adebug)
  (let ((ab (semantic-adebug-new-buffer "*SEMANTICDB*"))
	(db semanticdb-database-list))
    (semantic-adebug-insert-stuff-list db "*")))

;;;###autoload
(defalias 'semanticdb-adebug-database-list 'semanticdb-dump-all-table-summary)

;;;###autoload
(defun semanticdb-adebug-current-database ()
  "Run ADEBUG on the current database."
  (interactive)
  (require 'semantic-adebug)
  (let ((start (current-time))
	(p semanticdb-current-database)
	(end (current-time))
	(ab (semantic-adebug-new-buffer "*SEMANTICDB ADEBUG*"))
	)
    
    (semantic-adebug-insert-stuff-list p "*")))

;;;###autoload
(defun semanticdb-adebug-current-table ()
  "Run ADEBUG on the current database."
  (interactive)
  (require 'semantic-adebug)
  (let ((start (current-time))
	(p semanticdb-current-table)
	(end (current-time))
	(ab (semantic-adebug-new-buffer "*SEMANTICDB ADEBUG*"))
	)
    
    (semantic-adebug-insert-stuff-list p "*")))


;;;###autoload
(defun semanticdb-adebug-project-database-list ()
  "Run ADEBUG on the current database."
  (interactive)
  (require 'semantic-adebug)
  (let ((start (current-time))
	(p (semanticdb-current-database-list))
	(end (current-time))
	(ab (semantic-adebug-new-buffer "*SEMANTICDB ADEBUG*"))
	)
    
    (semantic-adebug-insert-stuff-list p "*")))



;;; Sanity Checks
;;

;;;###autoload
(defun semanticdb-table-oob-sanity-check (cache)
  "Validate that CACHE tags do not have any overlays in them."
  (while cache
    (when (semantic-overlay-p (semantic-tag-overlay cache))
      (message "Tag %s has an erroneous overlay!"
	       (semantic-format-tag-summarize (car cache))))
    (semanticdb-table-oob-sanity-check
     (semantic-tag-components-with-overlays (car cache)))
    (setq cache (cdr cache))))

;;;###autoload
(defun semanticdb-table-sanity-check (&optional table)
  "Validate the current semanticdb TABLE."
  (interactive)
  (if (not table) (setq table semanticdb-current-table))
  (let* ((full-filename (semanticdb-full-filename table))
	 (buff (get-file-buffer full-filename)))
    (if buff
	(save-excursion
	  (set-buffer buff)
	  (semantic-sanity-check))
      ;; We can't use the usual semantic validity check, so hack our own.
      (semanticdb-table-oob-sanity-check (semanticdb-get-tags table)))))

;;;###autoload
(defun semanticdb-database-sanity-check ()
  "Validate the current semantic database."
  (interactive)
  (let ((tables (semanticdb-get-database-tables
		 semanticdb-current-database)))
    (while tables
      (semanticdb-table-sanity-check (car tables))
      (setq tables (cdr tables)))
    ))



(provide 'semanticdb-debug)
;;; semanticdb-debug.el ends here