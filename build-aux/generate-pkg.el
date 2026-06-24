;;; generate-pkg.el --- generate jieba-rs-pkg.el -*- lexical-binding: t; -*-

(set-buffer (find-file-noselect "lisp/jieba-rs.el"))
(require 'package)
(let* ((desc (package-buffer-info))
       (name (symbol-name (package-desc-name desc)))
       (file (expand-file-name (format "%s-pkg.el" name)
                               (file-name-directory
                                (buffer-file-name)))))
  (with-temp-file file
    (pp (list 'define-package name
              (package-version-join
               (package-desc-version desc))
              (package-desc-summary desc)
              (list 'quote
                    (package-desc-reqs desc)))
        (current-buffer))))

;;; generate-pkg.el ends here
