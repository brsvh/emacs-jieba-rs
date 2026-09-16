;;; elfmt-tests.el --- Formatter regression tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Verify that formatting preserves Lisp data.

;;; Code:

(require 'ert)
(require 'elfmt)

(ert-deftest elfmt-tests-preserve-multiline-strings ()
  "Preserve literal whitespace with either indentation style."
  (dolist (style '("space" "tab"))
    (with-temp-buffer
      (emacs-lisp-mode)
      (setq-local editorconfig-properties-hash (make-hash-table))
      (puthash 'indent_style style editorconfig-properties-hash)
      (insert "(list
\t\"first
\tsecond
        third\")
")
      (let ((original (read (buffer-string))))
        (elfmt--indent-buffer)
        (should (equal original (read (buffer-string))))
        (let ((formatted (buffer-string)))
          (elfmt--indent-buffer)
          (should (equal formatted (buffer-string))))))))

(ert-deftest elfmt-tests-normalize-code-indentation ()
  "Normalize indentation outside string literals."
  (dolist (case '(("space" "\t(foo)" "        (foo)")
                  ("tab" "        (foo)" "\t(foo)")))
    (with-temp-buffer
      (emacs-lisp-mode)
      (setq-local editorconfig-properties-hash (make-hash-table))
      (puthash 'indent_style (car case) editorconfig-properties-hash)
      (insert (nth 1 case))
      (elfmt--normalize-indentation)
      (should (equal (buffer-string) (nth 2 case))))))

(ert-deftest elfmt-tests-save-preserves-string-whitespace ()
  "Honor EditorConfig trimming without changing saved Lisp values."
  (let* ((directory (make-temp-file "elfmt-save-" t))
         (file (expand-file-name "literal.el" directory))
         (source (concat "(list\n\t\"first  \n\tsecond\t \nlast\")  \n"
                         ";; Comment   \n")))
    (unwind-protect
        (dolist (trim '("true" "false"))
          (with-temp-file (expand-file-name ".editorconfig" directory)
            (insert "root=true\n[*.el]\nindent_style=space\n"
                    "trim_trailing_whitespace=" trim "\n"))
          (with-temp-file file (insert source))
          (elfmt--run (list file))
          (let ((formatted (with-temp-buffer
                             (insert-file-contents file)
                             (buffer-string))))
            (should (equal (read source) (read formatted)))
            (should (eq (not (null (string-match-p "Comment +\n" formatted)))
                        (equal trim "false")))
            (elfmt--run (list file))
            (with-temp-buffer
              (insert-file-contents file)
              (should (equal formatted (buffer-string))))))
      (delete-directory directory t))))

(ert-deftest elfmt-tests-save-preserves-escaped-whitespace ()
  "Keep literal character and symbol whitespace when trimming files."
  (let* ((directory (make-temp-file "elfmt-escaped-" t))
         (file (expand-file-name "literal.el" directory))
         (source (concat "(list ?\\   \n      ?\\\t  \n      ?   \n"
                         "      'foo\\   \n      'bar\\\t  \n"
                         "      'baz\\\\   \n)\n;; Comment\\   \n")))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".editorconfig" directory)
            (insert "root=true\n[*.el]\nindent_style=space\n"
                    "trim_trailing_whitespace=true\n"))
          (with-temp-file file (insert source))
          (elfmt--run (list file))
          (let ((formatted (with-temp-buffer
                             (insert-file-contents file)
                             (buffer-string))))
            (should (equal (read source) (read formatted)))
            (should-not (string-match-p "Comment\\\\ +\n" formatted))
            (should-not (string-match-p "baz\\\\\\\\ +\n" formatted))
            (elfmt--run (list file))
            (with-temp-buffer
              (insert-file-contents file)
              (should (equal formatted (buffer-string))))))
      (delete-directory directory t))))

(ert-deftest elfmt-tests-save-preserves-modified-whitespace ()
  "Keep whitespace characters with simple and combined modifiers."
  (let* ((directory (make-temp-file "elfmt-modified-" t))
         (file (expand-file-name "literal.el" directory)))
    (unwind-protect
        (dolist (style '("space" "tab"))
          (with-temp-file (expand-file-name ".editorconfig" directory)
            (insert "root=true\n[*.el]\nindent_style=" style
                    "\ntrim_trailing_whitespace=true\n"))
          (dolist (modifier '("\\C-" "\\M-" "\\s-" "\\S-" "\\A-" "\\H-"
                              "\\M-\\C-" "\\C-\\M-" "\\C-\\S-" "\\^"))
            (dolist (character '(" " "\t"))
              (let ((source (concat "(list ?" modifier character
                                    "  \n      nil)\n;; Comment   \n")))
                (with-temp-file file (insert source))
                (elfmt--run (list file))
                (let ((formatted (with-temp-buffer
                                   (insert-file-contents file)
                                   (buffer-string))))
                  (should (equal (read source) (read formatted)))
                  (should-not (string-match-p "Comment +\n" formatted))
                  (elfmt--run (list file))
                  (with-temp-buffer
                    (insert-file-contents file)
                    (should (equal formatted (buffer-string)))))))))
      (delete-directory directory t))))

(provide 'elfmt-tests)
;;; elfmt-tests.el ends here
