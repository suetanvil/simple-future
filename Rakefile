require 'rake'
require 'rspec/core/rake_task'
require 'yard'
 
RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = Dir.glob('spec/*_spec.rb')
end

YARD::Rake::YardocTask.new(:docs_via_yard) do |t|
  t.files = ['lib/*.rb']
  t.options = ['-r', 'README.md']
end

task :gem do
  `gem build simple-future.gemspec`
end

task :clean do
  gems = Dir.glob("simple-future-*.gem")
  rm gems if gems.size > 0
  rm_rf "doc"
end

task :clobber => [:clean] do
  rm_rf ".yardoc"
end

task :default => [:docs_via_yard, :test, :gem]
