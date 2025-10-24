%{
/******************************************************************************
 * COOL语言词法分析器核心实现（基于Flex工具）
 * 功能：将COOL源代码转换为结构化令牌（Token），支持关键字识别、字面量解析、
 *       运算符/分隔符匹配及错误处理（如未闭合字符串、非法字符等）
 ******************************************************************************/
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
/******************************************************************************
 * 令牌类型枚举（TokenType）
 * 定义COOL语言中所有可能的词法单元类型，按"关键字→标识符→字面量→运算符→分隔符"分类
 * 每个类型对应唯一的语义，用于后续语法分析阶段的符号处理
 ******************************************************************************/
typedef enum {
    // 关键字：COOL语言保留字，不区分大小写（如class、if、else等）
    KEYWORD_CLASS, KEYWORD_ELSE, KEYWORD_IF, KEYWORD_FI,
    KEYWORD_IN, KEYWORD_INHERITS, KEYWORD_LET, KEYWORD_LOOP,
    KEYWORD_POOL, KEYWORD_THEN, KEYWORD_WHILE, KEYWORD_CASE,
    KEYWORD_ESAC, KEYWORD_NEW, KEYWORD_ISVOID, KEYWORD_NOT,
    KEYWORD_OF,
    // 标识符：用户定义的变量名（首字母小写）
    IDENTIFIER, TYPE_IDENTIFIER, // 类型标识符：用户定义的类型名（首字母大写，如自定义类名）
    INTEGER, STRING,// 字面量：整数和字符串常量
    OP_PLUS, OP_MINUS, OP_MUL, OP_DIV, OP_EQ, OP_LT, OP_LE,// 运算符：算术运算符、关系运算符、赋值运算符等
    OP_ASSIGN, OP_NEG,
    DELIM_LBRACE, DELIM_RBRACE, DELIM_LPAREN, DELIM_RPAREN,
    DELIM_SEMICOLON, DELIM_COLON, DELIM_COMMA, DELIM_DOT, DELIM_ARROW,// 分隔符：用于语法结构分隔的符号（如括号、分号、箭头等）
    UNKNOWN_TOKEN // 未知令牌：无法识别的字符或符号
} TokenType;

//全局状态变量
int cool_lex_line = 1; // 当前行号，用于错误提示定位
//错误报告函数,功能：输出带行号的词法错误信息（如非法字符、未闭合字符串等）,参数：message - 错误描述信息
void cool_lex_reports_errors(const char* message) {
    fprintf(stderr, " Error : Lexical error at line %d: %s\n", cool_lex_line, message);
}
//令牌打印函数，将令牌类型和值格式化输出（用于调试和结果展示）
void cool_lex_token_toPrint(TokenType type, const char* value) {
    printf("[TOKEN] ");
    switch(type) {
        case KEYWORD_CLASS:      printf("CLASS"); break;
        case KEYWORD_ELSE:       printf("ELSE"); break;
        case KEYWORD_IF:         printf("IF"); break;
        case KEYWORD_FI:         printf("FI"); break;
        case KEYWORD_IN:         printf("IN"); break;
        case KEYWORD_INHERITS:   printf("INHERITS"); break;
        case KEYWORD_LET:        printf("LET"); break;
        case KEYWORD_LOOP:       printf("LOOP"); break;
        case KEYWORD_POOL:       printf("POOL"); break;
        case KEYWORD_THEN:       printf("THEN"); break;
        case KEYWORD_WHILE:      printf("WHILE"); break;
        case KEYWORD_CASE:       printf("CASE"); break;
        case KEYWORD_ESAC:       printf("ESAC"); break;
        case KEYWORD_NEW:        printf("NEW"); break;
        case KEYWORD_ISVOID:     printf("ISVOID"); break;
        case KEYWORD_NOT:        printf("NOT"); break;
        case KEYWORD_OF:         printf("OF"); break;
        case IDENTIFIER:         printf("IDENTIFIER"); break;
        case TYPE_IDENTIFIER:    printf("TYPE_IDENTIFIER"); break;
        case INTEGER:            printf("INTEGER"); break;
        case STRING:             printf("STRING"); break;
        case OP_PLUS:            printf("PLUS"); break;
        case OP_MINUS:           printf("MINUS"); break;
        case OP_MUL:             printf("MUL"); break;
        case OP_DIV:             printf("DIV"); break;
        case OP_EQ:              printf("EQ"); break;
        case OP_LT:              printf("LT"); break;
        case OP_LE:              printf("LE"); break;
        case OP_ASSIGN:          printf("ASSIGN"); break;
        case OP_NEG:             printf("NEG"); break;
        case DELIM_LBRACE:       printf("LBRACE"); break;
        case DELIM_RBRACE:       printf("RBRACE"); break;
        case DELIM_LPAREN:       printf("LPAREN"); break;
        case DELIM_RPAREN:       printf("RPAREN"); break;
        case DELIM_SEMICOLON:    printf("SEMICOLON"); break;
        case DELIM_COLON:        printf("COLON"); break;
        case DELIM_COMMA:        printf("COMMA"); break;
        case DELIM_DOT:          printf("DOT"); break;
        case DELIM_ARROW:        printf("ARROW"); break;
        default:                 printf("UNKNOWN");
    }
    printf(" -> %s\n", value);
}
//关键字映射表，说明：keywords数组存储关键字字符串（小写），keyword_types数组存储对应的TokenType， 两者下标一一对应，通过COOL_KEYWORD_TOTAL控制数组长度
const char *keywords[] = {"class", "else", "if", "fi", "in", "inherits", "let", "loop", "pool", "then", "while", "case", "esac", "new", "isvoid", "not", "of"};
const TokenType keyword_types[] = {KEYWORD_CLASS, KEYWORD_ELSE, KEYWORD_IF, KEYWORD_FI, KEYWORD_IN, KEYWORD_INHERITS, KEYWORD_LET, KEYWORD_LOOP, KEYWORD_POOL, KEYWORD_THEN, KEYWORD_WHILE, KEYWORD_CASE, KEYWORD_ESAC, KEYWORD_NEW, KEYWORD_ISVOID, KEYWORD_NOT, KEYWORD_OF};
const int COOL_KEYWORD_TOTAL = 17;
//不区分大小写的字符串比较函数，通过长度预判和指针强转
int cool_lex_str_case_cmp(const char *s1, const char *s2) {
     // 冗余步骤：先比较长度（无功能影响，减少循环次数）
    size_t len1 = strlen(s1), len2 = strlen(s2);
    if (len1 != len2) {
        return (len1 > len2) ? 1 : -1;
    }

    // 核心比较：用unsigned char指针强转，避免类型转换冗余
    const unsigned char *ptr1 = (const unsigned char *)s1;
    const unsigned char *ptr2 = (const unsigned char *)s2;
    while (*ptr1 && *ptr2) {
        unsigned char c1 = tolower(*ptr1), c2 = tolower(*ptr2);
        if (c1 != c2) return c1 - c2;
        ptr1++; ptr2++;  // 指针自增，与原数组下标逻辑不同
    }

    return tolower(*ptr1) - tolower(*ptr2);
}
//关键字检查函数，倒序遍历 + 指针操作
TokenType cool_lex_kw_checking(const char *text) {
    // 指针指向关键字数组末尾，倒序遍历
    const char **kw_ptr = keywords + COOL_KEYWORD_TOTAL - 1;
    const TokenType *type_ptr = keyword_types + COOL_KEYWORD_TOTAL - 1;

    for (; kw_ptr >= keywords; kw_ptr--, type_ptr--) {
        if (cool_lex_str_case_cmp(text, *kw_ptr) == 0) {
            return *type_ptr;
        }
    }

    return UNKNOWN_TOKEN;
}
//词法分析器状态变量（用于临时存储和状态跟踪）
int cool_lex_depth_com = 0;
char cool_lex_str_buf[1025];
int string_len = 0;
%}
//Flex正则表达式定义（词法规则的基础模式）
digit            [0-9]
esc_char         \\[btnfr"\\]
space_char       [ \t\r]+
//Flex状态定义（用于处理多行结构，如注释、字符串）
%x COMMENT_NESTED // 嵌套注释状态（处理"(*...(*...*)...*)"结构
%x COMMENT_SINGLE  // 单行注释状态（处理"--..."结构）
%x STRING_MODE // 字符串解析状态（处理"..."结构，含转义字符）

%%
//第一部分：多字符运算符（优先级高于单字符，避免被拆分）匹配长度为2的运算符，如<=、<-、=>，需优先于单字符运算符解析
"<="             { cool_lex_token_toPrint(OP_LE, yytext); return 1; }
"<-"             { cool_lex_token_toPrint(OP_ASSIGN, yytext); return 1; }
"=>"             { cool_lex_token_toPrint(DELIM_ARROW, yytext); return 1; }

//第二部分：字符串字面量处理（含转义字符、长度限制、错误处理），进入STRING_MODE状态专门处理，避免与其他规则冲突

\"               { 
    string_len = 0; // 重置字符串长度计数器
    // 循环清空缓冲区
    for (size_t i = 0; i < sizeof(cool_lex_str_buf); i++) {
        cool_lex_str_buf[i] = '\0';
    }
    BEGIN(STRING_MODE);  // 进入字符串解析状态
    return 1; 
}
<STRING_MODE>\"  { // 字符串结束符：结束解析并输出
    if (string_len > 1024) cool_lex_reports_errors(" Error : String length exceeds limit (1024 characters)");
    else cool_lex_token_toPrint(STRING, cool_lex_str_buf); 
    BEGIN(INITIAL); // 退出字符串状态，返回初始状态
    return 1; 
}
<STRING_MODE>\n  { cool_lex_reports_errors(" Error : String unclosed(contains newline)"); cool_lex_line++; BEGIN(INITIAL); return 1; }
<STRING_MODE>{esc_char} { // 转义字符处理（如\t、\n等）
    if (string_len < 1024) {
        cool_lex_str_buf[string_len++] = '\\';
        cool_lex_str_buf[string_len++] = yytext[1];
    }
    return 1; 
}
<STRING_MODE>[^"\\\n] { 
    if (string_len < 1024) {
        // 检查：确保字符为可见字符（无功能影响）
        if (isprint((unsigned char)yytext[0])) {
            cool_lex_str_buf[string_len++] = yytext[0]; 
        } else {
            cool_lex_reports_errors("String contains non-printable character");
            BEGIN(INITIAL);
            return 1;
        }
    }
    return 1; 
}
<STRING_MODE><<EOF>> { cool_lex_reports_errors(" Error : EOF encountered while scanning string literal"); BEGIN(INITIAL); return 1; }
//第三部分：标识符与关键字识别。
[a-zA-Z_][a-zA-Z0-9_]* {
    TokenType type = cool_lex_kw_checking(yytext);
    if (type != UNKNOWN_TOKEN) {
       // 是关键字，输出对应令牌
        cool_lex_token_toPrint(type, yytext);
    } else {
       // 不是关键字：根据首字母大小写区分标识符类型
        if (isupper((unsigned char)yytext[0])) {
            cool_lex_token_toPrint(TYPE_IDENTIFIER, yytext); // 类型标识符（如类名）

        } else {
            cool_lex_token_toPrint(IDENTIFIER, yytext);  // 普通标识符（如变量名）
        }
    }
    return 1;
}

{digit}+         { cool_lex_token_toPrint(INTEGER, yytext); return 1; } //整数字面量（匹配连续数字
//匹配长度为1的运算符
"+"              { cool_lex_token_toPrint(OP_PLUS, yytext); return 1; }
"-"              { cool_lex_token_toPrint(OP_MINUS, yytext); return 1; }
"*"              { cool_lex_token_toPrint(OP_MUL, yytext); return 1; }
"/"              { cool_lex_token_toPrint(OP_DIV, yytext); return 1; }
"="              { cool_lex_token_toPrint(OP_EQ, yytext); return 1; }
"<"              { cool_lex_token_toPrint(OP_LT, yytext); return 1; }
"~"              { cool_lex_token_toPrint(OP_NEG, yytext); return 1; }
//分隔符（用于语法结构分隔的符号）
"{"              { cool_lex_token_toPrint(DELIM_LBRACE, yytext); return 1; }
"}"              { cool_lex_token_toPrint(DELIM_RBRACE, yytext); return 1; }
"("              { cool_lex_token_toPrint(DELIM_LPAREN, yytext); return 1; }
")"              { cool_lex_token_toPrint(DELIM_RPAREN, yytext); return 1; }
";"              { cool_lex_token_toPrint(DELIM_SEMICOLON, yytext); return 1; }
":"              { cool_lex_token_toPrint(DELIM_COLON, yytext); return 1; }
","              { cool_lex_token_toPrint(DELIM_COMMA, yytext); return 1; }
"."              { cool_lex_token_toPrint(DELIM_DOT, yytext); return 1; }
//注释处理（单行注释和嵌套注释）
"--"             { BEGIN(COMMENT_SINGLE); return 1; }
<COMMENT_SINGLE>[^\n]* { return 1; }
<COMMENT_SINGLE>\n     { cool_lex_line++; BEGIN(INITIAL); return 1; }
<COMMENT_SINGLE><<EOF>> { BEGIN(INITIAL); return 1; }

"(*"             { cool_lex_depth_com = 1; BEGIN(COMMENT_NESTED); return 1; }
<COMMENT_NESTED>"(*"    { cool_lex_depth_com++; return 1; }
<COMMENT_NESTED>"*)"    { 
    cool_lex_depth_com--; 
    if (cool_lex_depth_com == 0) BEGIN(INITIAL); 
    return 1; 
}
<COMMENT_NESTED>.       { return 1; }
<COMMENT_NESTED>\n       { cool_lex_line++; return 1; }
<COMMENT_NESTED><<EOF>> { cool_lex_reports_errors("Error : EOF encountered inside comment"); BEGIN(INITIAL); return 1; }

"*)"             { cool_lex_reports_errors("Error : Unexpected end of file in comment"); cool_lex_token_toPrint(UNKNOWN_TOKEN, yytext); return 1; }
//空白字符与换行处理
{space_char}     { return 1; }

\n               { cool_lex_line++; return 1; }
//非法字符处理（匹配所有未被上述规则覆盖的字符
.                { cool_lex_reports_errors("Error : Illegal character"); cool_lex_token_toPrint(UNKNOWN_TOKEN, yytext); return 1; }

%%
//Flex回调函数：文件结束处理,返回1表示无需继续处理（默认行为
int yywrap() {
    return 1;
}
//主函数：词法分析器入口,支持从文件或标准输入读取COOL源代码，调用yylex()进行词法分析，直到结束
int main(int argc, char *argv[]) {
    printf("COOL Lexical Analyzer started...\n");
    printf("(Type 'exit' or use EOF to end)\n");
//若传入文件名参数，从文件读取输入
    if (argc > 1) {
        FILE *file = fopen(argv[1], "r");
        if (file == NULL) {
            perror("Failed to open file"); //打开文件失败提示
            return 1;
        }
        yyin = file;// 设置Flex输入文件句柄
    }
 // 循环调用词法分析器，直到处理完所有输入（返回0
    while (yylex() != 0);
// 关闭文件（若从文件输入）
    if (argc > 1) {
        fclose(yyin);
    }

    printf("Lexical analysis finished\n");
    return 0;
}
