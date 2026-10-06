module DoisC
  module Codegen
    class Emitter
      def initialize(@io : IO::Memory)
        @indent_level = 0
        @at_line_start = true
      end

      def indent
        @indent_level += 1
      end

      def dedent
        @indent_level -= 1
      end

      private def ensure_indent
        if @at_line_start
          @io << ("  " * @indent_level)
          @at_line_start = false
        end
      end

      def puts(input = "")
        if input.empty?
          @io << '\n'
          @at_line_start = true
        else
          ensure_indent
          @io << input
          @io << '\n'
          @at_line_start = true
        end
      end

      def <<(input : String)
        ensure_indent
        @io << input
        @at_line_start = false unless input.empty?
      end

      def with_indent(&)
        indent
        yield
        dedent
      end

      def clear
        @io.clear
        @indent_level = 0
        @at_line_start = true
      end

      def to_s
        @io.to_s
      end
    end
  end
end
