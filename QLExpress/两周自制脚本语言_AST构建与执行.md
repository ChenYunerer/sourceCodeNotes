---
title: 两周自制脚本语言_AST构建与执行
tags: 两周自制脚本语言
categories: 编译
data: 2022-03-12 12:04:14
---

# 两周自制脚本语言_AST构建与执行

## BNF表达方式说明

```
[part] 模式part重复出现0次或1次
{part} 模式part至少重复0次
part1 | part2 与par1或是part2匹配
() 将括号内容视为完整的模式
```

## BNF描述(不带方法调用)

```
primary  : "(" expr ")" | NUMBER | IDENTIFIER | STRING
factor   : "-" primary | primary
expr    : factor { OP factor }
block   : "{" [ statement ] {(";" | EOL) [ statement ]} "}" 
simple   : expr
statement : "if" expr block [ "else" block ]
      | "while" expr block
      | simple
program  : [ statement ] (";" | EOL)
```

NUMBER: 表示数字123等等

STRING: 表示字符串"111"“abc”等等

IDENTIFIER: 除上述两种以及一些特殊字符; ] } ) :等等外都属于IDENTIFIER

OP: 表示操作符 \+ - * / = == > < %

### expr例子

```
-1 + 2 - -(abc - -(1 + "123")) 
```

### statement例子

```
if expr  {
	if expr {
			expr;
			expr
			expr;
	}
} else {
	expr
	expr;
}
```

### program例子

```
statement;
```

```
;
```

```
EOL
```

## BNF描述(带方法调用)

```
primary : "fun" param_list block | ( "(" expr ")" | NUMBER | IDENTIFIER | STRING ) { postfix } 
factor   : "-" primary | primary
expr    : factor { OP factor }
block   : "{" [ statement ] {(";" | EOL) [ statement ]} "}"
simple : expr [ args ]
statement : "if" expr block [ "else" block ]
            | "while" expr block
            | simple
program : [ def | statement ] (";" | EOL)

param : IDENTIFIER
params : param { "," param }
param_list : "(" [ params ] ")"
def : "def" IDENTIFIER param_list block
args :expr{","expr}
postfix : "(" [ args ] ")"
```

def、param_list、params、param、block这几个非终结符定了一个方法的定义

```
def abc () {
	xxx
}
def abc (abc) {
	xxx
}
def abc (abc，bcd) {
	xxx
}
```

primary、postfix、args定义了方法的调用

```
abc()
abc(abc)
adb(abc, bcd)
```

primary第一个"fun" param_list block定义了闭包

## Parser解析树

![Parser](https://cdn.jsdelivr.net/gh/ChenYunerer/pics@master/uPic/Parser-2022-03-14%2022:38:38.svg)

### 举个例子

这个代码：

```
def addOne(a) {
a = a + 1;
}
a = addOne(10);
a;
```

对应的AST树为：

![AST例子](https://raw.githubusercontent.com/ChenYunerer/pics/master/uPic/AST例子.svg)
