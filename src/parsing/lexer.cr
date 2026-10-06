require "../ast_data/token"

module DoisC
  module Parsing
    # Lexes source Dois code into stream of tokens for the Parser to parse into an AST
    class Lexer
      def initialize(@source : String)
        @current = 0 # index
        @line = 1
        @column = 1
      end

      def lex : Array(Token)
        tokens = [] of Token
        loop do
          pass_whitespace
          break if eof?
          tokens << single_lex(advance)
        end

        tokens << new_token(TokenType::EOF, "")
        tokens
      end

      private def single_lex(c : Char) : Token
        case c
        when '='
          if match?('=')
            new_token(TokenType::COMP_EQ, "==")
          elsif match?('>')
            new_token(TokenType::ARROW, "=>")
          else
            new_token(TokenType::EQ, "=")
          end
        when '!'
          if match?('=')
            new_token(TokenType::COMP_NEQ, "!=")
          else
            new_token(TokenType::NOT, "!")
          end
        when '$'
          new_token(TokenType::FN_APPLY, "$")
        when '.'
          new_token(TokenType::PERIOD, ".")
        when '<'
          if match?('=')
            new_token(TokenType::COMP_LTEQ, "<=")
          else
            new_token(TokenType::COMP_LT, "<")
          end
        when '>'
          if match?('=')
            new_token(TokenType::COMP_GTEQ, ">=")
          else
            new_token(TokenType::COMP_GT, ">")
          end
        when '+'
          if match?('=')
            new_token(TokenType::ADD_ASSIGN, "+=")
          else
            new_token(TokenType::ADD, "+")
          end
        when '-'
          if match?('=')
            new_token(TokenType::SUB_ASSIGN, "-=")
          else
            new_token(TokenType::SUB, "-")
          end
        when '*'
          if match?('=')
            new_token(TokenType::MUL_ASSIGN, "*=")
          else
            new_token(TokenType::MUL, "*")
          end
        when '/'
          if match?('/')
            if match?('=')
              new_token(TokenType::IDIV_ASSIGN, "//=")
            else
              new_token(TokenType::IDIV, "//")
            end
          else
            if match?('=')
              new_token(TokenType::DIV_ASSIGN, "/=")
            else
              new_token(TokenType::DIV, "/")
            end
          end
        when '&'
          if match?('&')
            if match?('=')
              new_token(TokenType::AND_ASSIGN, "&&=")
            else
              new_token(TokenType::AND, "&&")
            end
          else
            if match?('=')
              new_token(TokenType::BITWISE_AND_ASSIGN, "&=")
            else
              new_token(TokenType::BITWISE_AND, "&")
            end
          end
        when '|'
          if match?('|')
            if match?('=')
              new_token(TokenType::OR_ASSIGN, "||=")
            else
              new_token(TokenType::OR, "||")
            end
          else
            if match?('=')
              new_token(TokenType::BITWISE_OR_ASSIGN, "|=")
            else
              new_token(TokenType::BAR, "|") # bitwise or / type or
            end
          end
        when '^'
          if match?('=')
            new_token(TokenType::BITWISE_XOR_ASSIGN, "^=")
          else
            new_token(TokenType::BITWISE_XOR, "^")
          end
        when '('
          new_token(TokenType::L_PAREN, "(")
        when ')'
          new_token(TokenType::R_PAREN, ")")
        when '['
          new_token(TokenType::L_BRACK, "[")
        when ']'
          new_token(TokenType::R_BRACK, "]")
        when '{'
          new_token(TokenType::L_BRACE, "{")
        when '}'
          new_token(TokenType::R_BRACE, "}")
        when ','
          new_token(TokenType::COMMA, ",")
        when '%'
          new_token(TokenType::MODULUS, "%")
        when ':'
          if match?(':')
            new_token(TokenType::DOUBLE_COLON, "::")
          else
            new_token(TokenType::COLON, ":")
          end
        when ';'
          new_token(TokenType::SEMICOLON, ";")
        when '?'
          new_token(TokenType::QUESTION, "?")
        when '0'..'9'
          number_token(c)
        when 'a'..'z', 'A'..'Z', '_'
          identifier_token(c)
        when '"'
          string_token
        when '\''
          char_token
        else
          raise error("Unknown character #{c}")
        end
      end

      private def new_token(type : TokenType, lexeme : String) : Token
        Token.new(type, lexeme, @line, @column - lexeme.size)
      end

      private def advance : Char
        c = @source[@current]
        @current += 1
        if c == '\n'
          @line += 1; @column = 1
        else
          @column += 1
        end
        c
      end

      # Int or Float literal
      private def number_token(first_char : Char) : Token
        start = @current - 1
        while !eof? && (peek.number? || peek == '.')
          advance
        end
        lexeme = @source[start...@current]
        type = if lexeme.includes?('.')
                 TokenType::FLOAT_LITERAL
               else
                 TokenType::INT_LITERAL
               end
        new_token(type, lexeme)
      end

      # keyword or identifier/operator token
      private def identifier_token(first_char : Char) : Token
        start = @current - 1
        while !eof? && (peek.alphanumeric? || peek == '_')
          advance
        end
        lexeme = @source[start...@current]
        type = ASTData::KEYWORDS[lexeme]? || TokenType::IDENTIFIER
        new_token(type, lexeme)
      end

      private def char_token : Token
        ch = peek
        advance
        if peek != '\''
          raise error("character literal cannot have more than one character")
        end
        advance
        new_token(TokenType::CHAR_LITERAL, "#{ch}")
      end

      private def string_token : Token
        start = @current
        start_ln, start_col = @line, @column
        until eof? || peek == '"'
          advance
        end
        if eof?
          # back line/column counters to start of string for more accurate error
          @line = start_ln; @column = start_col
          raise error("Unterminated string literal in program")
        end
        lexeme = @source[start...@current]
        advance
        new_token(TokenType::STRING_LITERAL, lexeme)
      end

      # tries to match expected and consumes if so
      private def match?(expected : Char) : Bool
        if !eof? && @source[@current] == expected
          @current += 1
          true
        else
          false
        end
      end

      private def peek : Char
        @source[@current]
      end

      private def pass_whitespace
        until eof?
          case peek
          when ' ', '\t', '\n', '\r'
            advance
          when '#' # only line based comments allowed for now
            until match?('\n') || eof?
              advance
            end
          else
            break
          end
        end
      end

      private def eof?
        @current >= @source.size
      end

      # TODO separate lexer errors from parser errors
      private def error(message : String) : ParseError
        ParseError.new(message, @line, @column)
      end
    end
  end
end
