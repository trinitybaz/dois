module DoisC
  module Codegen
    abstract class BaseCodegen
      protected getter emitter : Emitter

      def initialize(@emitter : Emitter)
      end

      protected def writeln(input = "")
        emitter.puts input
      end

      protected def write(input)
        emitter << input
      end

      protected def newline
        emitter.puts
      end

      protected def with_indent(&block)
        emitter.with_indent(&block)
      end

      protected def clear
        emitter.clear
      end

      protected def out
        emitter.to_s
      end
    end
  end
end
