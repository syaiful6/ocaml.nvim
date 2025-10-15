(comment) @comment
(type) @type
; (identifier) @identifier

(uid) @constant
(lid) @variable
["=" "|"] @operator
["<" ">" "[" "]" "(" ")" "{" "}"] @punctuation.bracket
[
  "%prec"
  "%left"
  "%right"
  "%nonassoc"
  "%token"
  "%attribute"
  "%parameter"
  "%on_error_reduce"
  "%type"
  "%start"
] @keyword
("%%") @punctuation.delimiter
