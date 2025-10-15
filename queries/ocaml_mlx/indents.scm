; inherits: ocaml

[
  (jsx_element_opening)
  (jsx_element_self_closing)
  (jsx_expression)
] @indent.begin

(jsx_element_opening
  (jsx_tag) @indent.begin)

(jsx_element_closing
  ">" @indent.end)

(jsx_element_self_closing
  "/>" @indent.end)

[
  (jsx_element_closing)
  ">"
] @indent.branch

; <button
; />
(jsx_element_self_closing
  "/>" @indent.branch)
