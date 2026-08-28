# Vendored rather than fetched.
#
# MacDown needs source positions in the rendered HTML so that a selection in
# one pane can be found in the other, and hoedown gives its renderers no way
# to know where in the source a block came from. That takes changes inside
# the library, which a fetched pod would discard on the next `pod install`.
#
# Kept as a pod rather than as loose files in the target so the header search
# paths and build settings stay exactly as they were.
Pod::Spec.new do |s|
  s.name         = 'hoedown'
  s.version      = '3.0.7'
  s.summary      = 'Standards compliant, fast, secure markdown processing library in C.'
  s.description  = 'Vendored fork of hoedown 3.0.7, patched to report source positions.'
  s.homepage     = 'https://github.com/hoedown/hoedown'
  s.license      = { :type => 'ISC', :file => 'LICENSE' }
  s.author       = { 'Natacha Porte' => '', 'Vincent Marti' => '',
                     'Devin Torres and the hoedown authors' => 'devin@devintorr.es' }
  s.source       = { :path => '.' }
  s.osx.deployment_target = '26.0'
  s.requires_arc = false
  s.source_files = 'src/*.{c,h}'
end
