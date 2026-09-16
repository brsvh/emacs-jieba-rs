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

(provide 'elfmt-tests)
;;; elfmt-tests.el ends here
