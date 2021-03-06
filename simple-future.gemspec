
Gem::Specification.new do |s|
  s.name        = 'simple-future'
  s.version     = '1.0.0'
  s.date        = '2018-01-17'
  s.summary     = "A Future class for simple process-based concurrency."
  s.description = <<-EOF
    SimpleFuture is class that simplifies coarse-grained concurrency using
    processes instead of threads.

    Each instance represents the future result of a block that is passed
    to it.  The block is evaluated in a forked child process and its result
    is returned to the SimpleFuture object.  This only works on Ruby
    implementations that provide Process.fork().
EOF
  s.authors     = ["Chris Reuter"]
  s.email       = 'chris@blit.ca'

  # I'm just going to add everything so that if you've got the gem,
  # you've also got the source distribution.  Yay! Open source!
  s.files       = ["README.md", "LICENSE.txt", "simple-future.gemspec",
                   "Rakefile", ".yardopts"] +
                  Dir.glob('doc/**/*') +
                  Dir.glob('{spec,lib}/*.rb')

  s.required_ruby_version = '>= 2.2.0'
  s.requirements << "A version of Ruby that implements Process.fork"

  s.add_development_dependency "rspec", '~> 3.7', '>= 3.7.0'
  s.add_development_dependency "yard", '~> 0.9.12', '>= 0.9.12'
  
  s.homepage    = 'https://github.com/suetanvil/simple-future'
  s.license     = 'MIT'
end
