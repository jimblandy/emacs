;;; finder.el --- topic & keyword-based code finder

;; Copyright (C) 1992 Free Software Foundation, Inc.

;; Author: Eric S. Raymond <esr@snark.thyrsus.com>
;; Created: 16 Jun 1992
;; Version: 1.0
;; Keywords: help

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; This mode uses the Keywords library header to provide code-finding
;; services by keyword.
;;
;; Things to do:
;;    1. Support multiple keywords per search.  This could be extremely hairy;
;; there doesn't seem to be any way to get completing-read to exit on
;; an EOL with no substring pending, which is what we'd want to end the loop.
;;    2. Search by string in synopsis line?
;;    3. Function to check finder-package-info for unknown keywords.

;;; Code:

(require 'lisp-mnt)
(require 'finder-inf)

;; Local variable in finder buffer.
(defvar finder-headmark)

(defvar finder-known-keywords
  '(
    (abbrev	. "abbreviation handling, typing shortcuts, macros")
    (bib	. "code related to the `bib' bibliography processor")
    (c		. "support for the C language and related languages")
    (calendar	. "calendar and time management support")
    (comm	. "communications, networking, remote access to files")
    (data	. "support editing files of data")
    (docs	. "support for Emacs documentation")
    (emulations	. "emulations of other editors")
    (extensions	. "Emacs Lisp language extensions")
    (faces	. "support for multiple fonts")
    (frames     . "support for Emacs frames and window systems")
    (games	. "games, jokes and amusements")
    (hardware	. "support for interfacing with exotic hardware")
    (help	. "support for on-line help systems")
    (hypermedia . "support for links between text or other media types")
    (i18n	. "internationalization and alternate character-set support")
    (internal	. "code for Emacs internals, build process, defaults")
    (languages	. "specialized modes for editing programming languages")
    (lisp	. "Lisp support, including Emacs Lisp")
    (local	. "code local to your site")
    (maint	. "maintenance aids for the Emacs development group")
    (mail	. "modes for electronic-mail handling")
    (matching	. "various sorts of searching and matching")
    (mouse	. "mouse support")
    (news	. "support for netnews reading and posting")
    (oop        . "support for object-oriented programming")
    (outlines   . "support for hierarchical outlining")
    (processes	. "process, subshell, compilation, and job control support")
    (terminals	. "support for terminal types")
    (tex	. "code related to the TeX formatter")
    (tools	. "programming tools")
    (unix	. "front-ends/assistants for, or emulators of, UNIX features")
    (vms	. "support code for vms")
    (wp		. "word processing")
    ))

(defvar finder-mode-map nil)
(or finder-mode-map
    (let ((map (make-sparse-keymap)))
      (define-key map " "	'finder-select)
      (define-key map "f"	'finder-select)
      (define-key map "\C-m"	'finder-select)
      (define-key map "?"	'finder-summary)
      (define-key map "q"	'finder-exit)
      (define-key map "d"	'finder-list-keywords)
      (setq finder-mode-map map)))


;;; Code for regenerating the keyword list.

(defvar finder-package-info nil
  "Assoc list mapping file names to description & keyword lists.")

(defun finder-compile-keywords (&rest dirs)
  "Regenerate the keywords association list into the file `finder-inf.el'.
Optional arguments are a list of Emacs Lisp directories to compile from; no
arguments compiles from `load-path'."
  (save-excursion
    (let ((processed nil))
      (find-file "finder-inf.el")
      (erase-buffer)
      (insert ";;; finder-inf.el --- keyword-to-package mapping\n")
      (insert ";; Keywords: help\n")
      (insert ";;; Commentary:\n")
      (insert ";; Don't edit this file.  It's generated by finder.el\n\n")
      (insert ";;; Code:\n")
      (insert "\n(setq finder-package-info '(\n")
      (mapcar
       (lambda (d)
	 (mapcar
	  (lambda (f) 
	    (if (and (string-match "^[^=].*\\.el$" f)
		     (not (member f processed)))
		(let (summary keystart keywords)
		  (setq processed (cons f processed))
		  (save-excursion
		    (set-buffer (get-buffer-create "*finder-scratch*"))
		    (buffer-disable-undo (current-buffer))
		    (erase-buffer)
		    (insert-file-contents
		     (concat (file-name-as-directory (or d ".")) f))
		    (setq summary (lm-synopsis))
		    (setq keywords (lm-keywords)))
		  (insert
		   (format "    (\"%s\"\n        " f))
		  (prin1 summary (current-buffer))
		  (insert
		   "\n        ")
		  (setq keystart (point))
		  (insert
		   (if keywords (format "(%s)" keywords) "nil")
		   ")\n")
		  (subst-char-in-region keystart (point) ?, ? )
		  )))
	  (directory-files (or d "."))))
       (or dirs load-path))
      (insert "))\n\n(provide 'finder-inf)\n\n;;; finder-inf.el ends here\n")
      (kill-buffer "*finder-scratch*")
      (eval-current-buffer) ;; So we get the new keyword list immediately
      (basic-save-buffer))))

(defun finder-compile-keywords-make-dist ()
  "Regenerate `finder-inf.el' for the Emacs distribution."
  (apply 'finder-compile-keywords command-line-args-left)
  (kill-emacs))

;;; Now the retrieval code

(defun finder-insert-at-column (column &rest strings)
  "Insert list of STRINGS, at column COLUMN."
  (if (> (current-column) column) (insert "\n"))
  (move-to-column column)
  (let ((col (current-column)))
    (if (< col column)
	(indent-to column)
      (if (and (/= col column)
	       (= (preceding-char) ?\t))
	  (let (indent-tabs-mode)
	    (delete-char -1)
            (indent-to col)
            (move-to-column column)))))
  (apply 'insert strings))

(defun finder-list-keywords ()
  "Display descriptions of the keywords in the Finder buffer."
  (interactive)
  (if (get-buffer "*Finder*")
      (pop-to-buffer "*Finder*")
    (pop-to-buffer (set-buffer (get-buffer-create "*Finder*")))
    (finder-mode)
    (setq buffer-read-only nil)
    (erase-buffer)
    (mapcar
     (lambda (assoc)
       (let ((keyword (car assoc)))
	 (insert (symbol-name keyword))
	 (finder-insert-at-column 14 (concat (cdr assoc) "\n"))
	 (cons (symbol-name keyword) keyword)))
     finder-known-keywords)
    (goto-char (point-min))
    (setq finder-headmark (point))
    (setq buffer-read-only t)
    (set-buffer-modified-p nil)
    (balance-windows)
    (finder-summary)))

(defun finder-list-matches (key)
  (pop-to-buffer (set-buffer "*Finder Category*"))
  (finder-mode)
  (setq buffer-read-only nil)
  (erase-buffer)
  (let ((id (intern key)))
    (insert
     "The following packages match the keyword `" key "':\n\n")
    (setq finder-headmark (point))
    (mapcar
     (lambda (x)
       (if (memq id (car (cdr (cdr x))))
	   (progn
	     (insert (car x))
	     (finder-insert-at-column 16 (concat (car (cdr x)) "\n")))))
     finder-package-info)
    (goto-char (point-min))
    (forward-line)
    (setq buffer-read-only t)
    (set-buffer-modified-p nil)
    (shrink-window-if-larger-than-buffer)
    (finder-summary)))

;; Search for a file named FILE the same way `load' would search.
(defun finder-find-library (file)
  (if (file-name-absolute-p file)
      file
    (let ((dirs load-path)
	  found)
      (while (and dirs (not found))
	(if (file-exists-p (expand-file-name (concat file ".el") (car dirs)))
	    (setq found (expand-file-name file (car dirs)))
	  (if (file-exists-p (expand-file-name file (car dirs)))
	      (setq found (expand-file-name file (car dirs)))))
	(setq dirs (cdr dirs)))
      found)))

(defun finder-commentary (file)
  (interactive)
  (let* ((str (lm-commentary (finder-find-library file))))
    (if (null str)
	(error "Can't find any Commentary section"))
    (pop-to-buffer "*Finder*")
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert str)
    (goto-char (point-min))
    (delete-blank-lines)
    (goto-char (point-max))
    (delete-blank-lines)
    (goto-char (point-min))
    (while (re-search-forward "^;+ ?" nil t)
      (replace-match "" nil nil))
    (goto-char (point-min))
    (setq buffer-read-only t)
    (set-buffer-modified-p nil)
    (shrink-window-if-larger-than-buffer)
    (finder-summary)))

(defun finder-current-item ()
  (if (and finder-headmark (< (point) finder-headmark))
      (error "No keyword or filename on this line")
    (save-excursion
      (beginning-of-line)
      (current-word))))

(defun finder-select ()
  (interactive)
  (let ((key (finder-current-item)))
    (if (string-match "\\.el$" key)
	(finder-commentary key)
      (finder-list-matches key))))

(defun finder-by-keyword ()
  "Find packages matching a given keyword."
  (interactive)
  (finder-list-keywords))

(defun finder-mode ()
  "Major mode for browsing package documentation.
\\<finder-mode-map>
\\[finder-select]	more help for the item on the current line
\\[finder-exit]	exit Finder mode and kill the Finder buffer.
"
  (interactive)
  (use-local-map finder-mode-map)
  (set-syntax-table emacs-lisp-mode-syntax-table)
  (setq mode-name "Finder")
  (setq major-mode 'finder-mode)
  (make-local-variable 'finder-headmark)
  (setq finder-headmark nil))

(defun finder-summary ()
  "Summarize basic Finder commands."
  (interactive)
  (message "%s"
   (substitute-command-keys
    "\\<finder-mode-map>\\[finder-select] = select, \\[finder-list-keywords] = to finder directory, \\[finder-exit] = quit, \\[finder-summary] = help")))

(defun finder-exit ()
  "Exit Finder mode and kill the buffer"
  (interactive)
  (delete-window)
  (kill-buffer "*Finder*"))

(provide 'finder)

;;; finder.el ends here
