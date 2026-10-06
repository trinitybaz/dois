require "./compilation_error"
require "./ast_data/ast"
require "./parsing/parser"
require "./type_checking/checker"
require "./codegen/transpiler"
require "colorize"

module DoisC
  class CLI
    def initialize(@args : Array(String))
    end

    def run
      source_path = parse_args
      source = read_source(source_path)
      begin
        ast = parse(source, source_path)
        type_check(ast, source_path)
        generate_c(ast, source_path)
      rescue ex : DoisC::Parsing::ParseError
        handle_parse_error(source_path, ex)
      rescue ex : DoisC::TypeChecking::TypeError
        handle_type_error(source_path, ex)
      end
    end

    private def parse_args : String
      if @args.empty?
        puts "Usage: doisc <source_file>"
        exit(1)
      end

      @args.first.strip
    end

    private def read_source(path : String) : String
      File.read(path)
    end

    private def parse(source : String, path : String)
      log("Parsing #{path}...")
      ast = DoisC::Parsing::Parser.new(source).parse
      success("Parsed successfully!")
      puts
      ast
    end

    private def type_check(ast, path : String)
      log("Type checking #{path}...")
      DoisC::TypeChecking::TypeChecker.new.check(ast)
      success("Type checked successfully!")
      puts
    end

    private def generate_c(ast, path : String)
      log("Generating C #{path}...")

      transpiler = DoisC::Codegen::Transpiler.new(IO::Memory.new)
      generated_c = transpiler.transpile(ast)

      output_path = "./out.c"
      File.write(output_path, generated_c)

      success("Generated C successfully -> #{output_path}")
    end

    private def log(msg : String)
      puts msg.colorize(100, 100, 100)
    end

    private def success(msg : String)
      puts msg.colorize(100, 200, 100)
    end

    private def handle_parse_error(path : String, ex)
      puts "#{path}:#{ex.message}".colorize(220, 120, 120)
      ex.put_backtrace
    end

    private def handle_type_error(path : String, ex)
      puts "#{path}:#{ex}".colorize(220, 120, 120)
      ex.put_backtrace
    end
  end
end

DoisC::CLI.new(ARGV).run
