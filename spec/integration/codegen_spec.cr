require "../spec_helper"
require "../../src/parsing/parser"
require "../../src/type_checking/checker"
require "../../src/codegen/transpiler"

module DoisC
  describe "codegen integration" do
    it "emits proc main as dois_main" do
      source = <<-DOIS
        module MyModule has
          proc main() do
            let x : Int = 5;
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("void dois_main(void)")
      c_source.should contain("int main(void)")
    end

    it "lowers arithmetic expressions into C operators" do
      source = <<-DOIS
        module MyModule has
          proc main() do
            let x : Int = 5;
            let y : Int = 10;
            let z = x + y;
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("int64_t z = (x + y);")
    end

    it "lowers builtin print for ints" do
      source = <<-DOIS
        module MyModule has
          proc main() do
            print(5);
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("dois_print_int(5);")
    end

    it "lowers product construction to a C compound literal" do
      source = <<-DOIS
        module MyModule has
          type Box has
            value : Int
          end

          proc main() do
            let b = Box(value = 5);
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("struct Box b = (struct Box){.value = 5};")
    end

    it "lowers field access on local product values" do
      source = <<-DOIS
        module MyModule has
          type Box has
            value : Int
          end

          proc main() do
            let b = Box(value = 5);
            print(b.value);
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("dois_print_int(b.value);")
    end

    it "lowers function calls to mangled C function names" do
      source = <<-DOIS
        module MyModule has
          fn add$(x : Int, y : Int) : Int =>
            x + y
          end

          proc main() do
            let s = add$(2, 3);
            print(s);
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("int64_t s = add(2, 3);")
      c_source.should contain("dois_print_int(s);")
    end

    it "prefers local bindings over global function names in generated code" do
      source = <<-DOIS
        module MyModule has
          fn foo$() : Int =>
            5
          end

          proc main() do
            let foo = 6;
            print(foo);
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("int64_t foo = 6;")
      c_source.should contain("dois_print_int(foo);")
      c_source.should_not contain("dois_print_int(MyModule__foo);")
    end

    it "emits prelude Result and Err definitions without user declarations" do
      source = <<-DOIS
        module MyModule has
          proc main() do
            let x : Int = 5;
          end
        end
        DOIS

      c_source = compile_to_c(source)
      c_source.should contain("struct Result {")
      c_source.should contain("struct Err {")
    end

    it "compiles and runs field access from a constructed product" do
      source = <<-DOIS
        module MyModule has
          type Box has
            value : Int
          end

          proc main() do
            let b = Box(value = 5);
            print(b.value);
          end
        end
        DOIS

      output = compile_and_run_c(source)
      output.should eq("5\n")
    end

    it "compiles and runs local shadowing over a function name" do
      source = <<-DOIS
        module MyModule has
          fn foo$() : Int =>
            5
          end

          proc main() do
            print(foo$());
            let foo = 6;
            print(foo);
          end
        end
        DOIS

      output = compile_and_run_c(source)
      output.should eq("5\n6\n")
    end

    it "compiles and runs a small observable program" do
      source = <<-DOIS
        module MyModule has
          fn foo$() : Int =>
            5
          end

          fn add$(x : Int, y : Int) : Int =>
            x + y
          end

          proc main() do
            print(foo$());
            let x = 6;
            print(x);
            print(add$(4, 11));
          end
        end
        DOIS

      output = compile_and_run_c(source)
      output.should eq("5\n6\n15\n")
    end
  end
end
