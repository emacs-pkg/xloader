;;; xloader.el --- Loader for configuration files

;; Author: IMAKADO <ken.imakado@gmail.com>
;; URL: https://github.com/emacs-jp/init-loader/
;; Version: 0.02
;; Package-Requires: ((cl-lib "0.5"))

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Place xloader.el somewhere in your `load-path'.  Then, add the
;; following lines to ~/.emacs or ~/.emacs.d/init.el:
;;
;;     (require 'xloader)
;;     (xloader-load "/path/to/init-directory")
;;
;; The last line loads configuration files in /path/to/init-directory.
;; If you omit arguments for `xloader-load', the value of
;; `xloader-directory' is used.
;;
;; Note that not all files in the directory are loaded.  Each file is
;; examined that if it is a .el or .elc file and, it has a valid name
;; specified by `xloader-default-regexp' or it is a platform
;; specific configuration file.
;;
;; By default, valid names of configuration files start with two
;; digits.  For example, the following file names are all valid:
;;     00_util.el
;;     01_ik-cmd.el
;;     21_javascript.el
;;     99_global-keys.el
;;
;; Files are loaded in the lexicographical order.  This helps you to
;; resolve dependency of the configurations.
;;
;; A platform specific configuration file has a prefix corresponds to
;; the platform.  The following is the list of prefixes and platform
;; specific configuration files are loaded in the listed order after
;; non-platform specific configuration files.
;;
;; Platform   Subplatform        Prefix         Example
;; ------------------------------------------------------------------------
;; Windows                       windows-       windows-fonts.el
;;            Meadow             meadow-        meadow-commands.el
;; ------------------------------------------------------------------------
;; Mac OS X   Carbon Emacs       carbon-emacs-  carbon-emacs-applescript.el
;;            Cocoa Emacs        cocoa-emacs-   cocoa-emacs-plist.el
;; ------------------------------------------------------------------------
;; GNU/Linux                     linux-         linux-commands.el
;; ------------------------------------------------------------------------
;; *BSD                          bsd-           bsd-commands.el
;; ------------------------------------------------------------------------
;; All        Non-window system  nw-            nw-key.el
;;
;; If `xloader-byte-compile' is non-nil, each configuration file
;; is byte-compiled when it is loaded.  If you modify the .el file,
;; then it is recompiled next time it is loaded.
;;
;; Loaded files and errors during the loading process are recorded.
;; If `xloader-show-log-after-init' is `t', the record is
;; shown after the overall loading process. If `xloader-show-log-after-init`
;; is `'error-only', the record is shown only error occured.
;; You can do this manually by M-x xloader-show-log.
;;

;;; Code:

(require 'cl-lib)
(require 'benchmark)
(require 'xprint)

;;; customize-variables
(defgroup xloader nil
  "Loader of configuration files."
  :prefix "xloader-"
  :group 'initialization)

(defcustom xloader-directory
  (expand-file-name (concat (if (boundp 'user-emacs-directory)
                                (file-name-as-directory user-emacs-directory)
                              "~/.emacs.d/")
                            "inits"))
  "Default directory of configuration files."
  :type 'directory)

(defcustom xloader-show-log-after-init t
  "Show loading log message if this value is t. If this value is `error-only',
log message is shown only errors occured."
  :type 'boolean)

(defcustom xloader-byte-compile nil
  "Byte-compile configuration files if this value is non-nil."
  :type 'boolean)

(defcustom xloader-default-regexp "\\(?:\\`[[:digit:]]\\{2\\}\\)"
  "Regular expression determining valid configuration file names.

The default value matches files that start with two digits.  For
example, 00_foo.el, 01_bar.el ... 99_keybinds.el."
  :type 'regexp)

(defcustom xloader-meadow-regexp "\\`meadow-"
  "Regular expression of Meadow specific configuration file names."
  :type 'regexp)

(defcustom xloader-windows-regexp "\\`windows-"
  "Regular expression of Windows specific configuration file names."
  :type 'regexp)

(defcustom xloader-carbon-emacs-regexp "\\`carbon-emacs-"
  "Regular expression of Carbon Emacs specific configuration file names."
  :type 'regexp)

(defcustom xloader-cocoa-emacs-regexp "\\`cocoa-emacs-"
  "Regular expression of Cocoa Emacs specific configuration file names."
  :type 'regexp)

(defcustom xloader-nw-regexp "\\`nw-"
  "Regular expression of no-window Emacs configuration file names."
  :type 'regexp)

(defcustom xloader-linux-regexp "\\`linux-"
  "Regular expression of GNU/Linux specific configuration file names."
  :type 'regexp)

(defcustom xloader-bsd-regexp "\\`bsd-"
  "Regular expression of *BSD specific configuration file names."
  :type 'regexp)

;;;###autoload
(cl-defun xloader-load (&optional (init-dir xloader-directory))
  "Load configuration files in INIT-DIR."
  (let ((init-dir (xloader-follow-symlink init-dir))
        (is-carbon-emacs nil))
    (cl-assert (and (stringp init-dir) (file-directory-p init-dir)))
    (xloader-re-load xloader-default-regexp init-dir t)

    ;; Windows
    (when (featurep 'dos-w32)
      (xloader-re-load xloader-windows-regexp init-dir))
    ;; meadow
    (when (featurep 'meadow)
      (xloader-re-load xloader-meadow-regexp init-dir))

    ;; Carbon Emacs
    (when (featurep 'carbon-emacs-package)
      (xloader-re-load xloader-carbon-emacs-regexp init-dir)
      (setq is-carbon-emacs t))
    ;; Cocoa Emacs
    (when (or (memq window-system '(ns mac))
              (and (not is-carbon-emacs) ;; for daemon mode
                   (not window-system)
                   (eq system-type 'darwin)))
      (xloader-re-load xloader-cocoa-emacs-regexp init-dir))

    ;; GNU Linux
    (when (eq system-type 'gnu/linux)
      (xloader-re-load xloader-linux-regexp init-dir))

    ;; *BSD
    (when (eq system-type 'berkeley-unix)
      (xloader-re-load xloader-bsd-regexp init-dir))

    ;; no-window
    (when (not window-system)
      (xloader-re-load xloader-nw-regexp init-dir))

    (cl-case xloader-show-log-after-init
      (error-only (add-hook 'after-init-hook 'xloader--show-log-error-only))
      ('t (add-hook 'after-init-hook 'xloader-show-log)))))

(defun xloader-follow-symlink (dir)
  (cond ((file-symlink-p dir)
         (expand-file-name (file-symlink-p dir)))
        (t (expand-file-name dir))))

(defvar xloader--log-buffer nil)
(defun xloader-log (&optional msg)
  (if msg
      (when (stringp msg)
        (push msg xloader--log-buffer))
    (mapconcat 'identity (reverse xloader--log-buffer) "\n")))

(defvar xloader--error-log-buffer nil)
(defun xloader-error-log (&optional msg)
  (if msg
      (when (stringp msg)
        (push msg xloader--error-log-buffer))
    (mapconcat 'identity (reverse xloader--error-log-buffer) "\n")))

(defvar xloader-before-compile-hook nil)
(defun xloader-load-file (file)
  (when xloader-byte-compile
    (let* ((path (file-name-sans-extension (locate-library file)))
           (el (concat path ".el")) (elc (concat path ".elc")))
      (when (and (not (file-exists-p el)) (file-exists-p elc))
        (error "There is only byte-compiled file."))
      (when (or (not (file-exists-p elc))
                (file-newer-than-file-p el elc))
        (when (file-exists-p elc) (delete-file elc))
        (run-hook-with-args 'xloader-before-compile-hook file)
        (byte-compile-file el))))
  (xdump file)
  (xsleep 0)
  (load file))

(defun xloader-re-load (re dir &optional sort)
  ;; 2011/JUN/12 zqwell: Don't localize `load-path' and use it as global
  (add-to-list 'load-path dir)
  (dolist (el (xloader--re-load-files re dir sort))
    (condition-case e
        (let ((time (car (benchmark-run (xloader-load-file (file-name-sans-extension el))))))
          (xloader-log (format "loaded %s. %s" (locate-library el) time)))
      (error
       ;; 2011/JUN/12 zqwell: Improve error message
       ;; See. http://d.hatena.ne.jp/kitokitoki/20101205/p1
       (xloader-error-log (format "%s. %s" (locate-library el) (error-message-string e)))))))

;; 2011/JUN/12 zqwell Read first byte-compiled file if it exist.
;; See. http://twitter.com/#!/fkmn/statuses/21411277599
(defun xloader--re-load-files (re dir &optional sort)
  (cl-loop for el in (directory-files dir t)
           when (and (string-match re (file-name-nondirectory el))
                     (or (string-match "elc\\'" el)
                         (and (string-match "el\\'" el)
                              (not (locate-library (concat el "c"))))))
           collect (file-name-nondirectory el) into ret
           finally return (if sort (sort ret 'string<) ret)))

(defun xloader--show-log-error-only ()
  (let ((err (xloader-error-log)))
    (when (and err (not (string= err "")))
      (xloader-show-log))))

;;;###autoload
(defun xloader-show-log ()
  "Show xloader log buffer."
  (interactive)
  (let ((b (get-buffer-create "*init log*")))
    (with-current-buffer b
      (view-mode -1)
      (erase-buffer)
      (insert "------- error log -------\n\n"
              (xloader-error-log)
              "\n\n")
      (insert "------- init log -------\n\n"
              (xloader-log)
              "\n\n")
      ;; load-path
      (insert "------- load path -------\n\n"
              (mapconcat 'identity load-path "\n"))
      (goto-char (point-min)))
    (switch-to-buffer b)
    (view-mode +1)))

(provide 'xloader)

;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; xloader.el ends here
