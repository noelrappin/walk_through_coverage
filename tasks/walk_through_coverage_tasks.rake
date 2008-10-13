require 'hpricot'
require 'open-uri'

class WalkThroughRcovTask < Rcov::RcovTask 
  
  def define
    lib_path = @libs.join(File::PATH_SEPARATOR)
    actual_name = Hash === name ? name.keys.first : name
    unless Rake.application.last_comment
      desc "Analyze code coverage with tests" + 
        (@name==:rcov ? "" : " for #{actual_name}")
    end
    task @name do
      run_code = ''
      RakeFileUtils.verbose(@verbose) do
        run_code =
            case rcov_path
            when nil, ''
              "-S rcov"
            else %!"#{rcov_path}"!
            end
        ruby_opts = @ruby_opts.clone
        ruby_opts.push( "-I#{lib_path}" )
        ruby_opts.push run_code
        ruby_opts.push( "-w" ) if @warning
      
        command = ruby_opts.join(" ") + " " + option_list +
          %[ -o "#{@output_dir}" ] +
          file_list.collect { |fn| %["#{fn}"] }.join(' ')
        ruby command rescue nil
      end
    end

    desc "Remove rcov products for #{actual_name}"
    task paste("clobber_", actual_name) do
      #rm_r @output_dir rescue nil
    end

    clobber_task = paste("clobber_", actual_name)
    task :clobber => [clobber_task]

    task actual_name => clobber_task
    self
  end
  
end

class CoverageResult
  
  attr_accessor :result_file, :lines, :locs, :total_cov, :code_cov
  
  def initialize(filename)
    @result_file = filename.split("/")[-1]
    doc = Hpricot(open(filename))
    @lines = (doc/".lines_total tt").first.inner_html.to_i
    @locs = (doc/".lines_code tt").first.inner_html.to_i
    @total_cov = (doc/".coverage_total").first.inner_html.to_i
    @code_cov = (doc/".coverage_code").first.inner_html.to_i
  end
  
  def to_table_row
    "<tr>" +
    "<td><a href='#{result_file}'>#{result_file}</td>" +
    "<td>#{lines}</td>" +
    "<td>#{locs}</td>" +
    "<td>#{total_cov}</td>" +
    "<td>#{code_cov}</td>" +
    "</tr>"
  end
  
end

namespace :test do
  
  namespace :walk_through do
    
    desc "Delete aggregate coverage data."
    task :clean do 
      rm_rf "walk_through" 
      mkdir "walk_through"
    end
    
    task :aggregate do
      results = FileList["walk_through/*_rb.html"].map { |f| CoverageResult.new(f)}
      File.open("walk_through/walk_through_result.html", "w") do |f|
        f << "<table>"
        f << "<tr><th>Name</th><th>Lines</th><th>LOC</th><th>Total Coverage</th><th>Code Coverage</th>"
        results.sort_by(&:code_cov).each do |result|
          f << result.to_table_row
        end
        f << "</table>"
      end
    end

  end
    
  task :walk_through => "test:walk_through:clean"
  def create_file_task(filename)
    file = File.basename(filename, ".rb")
    return if FileList["test/**/#{file}_test.rb"].empty?
    namespace :walk_through do
      WalkThroughRcovTask.new(file) do |t|
        t.libs << "test"
        t.test_files = FileList["test/**/#{file}_test.rb"]
        t.verbose = true
        t.rcov_opts << '--rails'
        t.rcov_opts << '--exclude /Library/Ruby/'
        t.rcov_opts << '--exclude lib'
        t.rcov_opts << '--exclude app'
        t.rcov_opts << '--exclude db'
        #t.rcov_opts << '--no-rcovrt'
        t.rcov_opts << "-i #{filename}"
        t.output_dir = "walk_through"
      end
    end
    task :walk_through => "test:walk_through:#{file}"
  end
  
  FileList["app/controllers/*_controller.rb"].each do |controller|
    create_file_task(controller)
  end
  
  FileList["app/helpers/*_helper.rb"].each do |helper|
    create_file_task(helper)
  end
  
  FileList["app/models/*.rb"].each do |model|
    create_file_task(model)
  end
  
  task :walk_through => "test:walk_through:aggregate"
  
end