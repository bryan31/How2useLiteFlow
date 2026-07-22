# LiteFlow EL 规则全集（v2.16.X）

> 来源文档（相对 `04.v2.16.X文档/`）：
> - `070.🧩EL规则/010.说明.md`、`020.串行编排.md`、`030.并行编排.md`、`040.选择编排.md`、`050.条件编排.md`
> - `070.🧩EL规则/060.循环编排.md`、`070.异步循环模式.md`、`080.捕获异常表达式.md`、`090.与或非表达式.md`
> - `070.🧩EL规则/100.使用子流程.md`、`110.使用子变量.md`、`120.复杂编排例子.md`、`130.前置和后置编排.md`
> - `070.🧩EL规则/140.🍉组件参数语法/000~030`（说明/tag/data/bind）
> - `070.🧩EL规则/150.重试语法.md`、`160.超时控制语法.md`、`170.链路继承.md`、`180.验证规则.md`、`190.关于注释.md`、`200.关于分号.md`、`210.组件名包装.md`
>
> 版本对齐：LiteFlow **v2.16.X**。文中所有 `<Badge text="vX.X.X+"/>` 标注均来自原文，表示该特性从该版本起支持。

---

## 1. EL 总述

LiteFlow 从 2.8.X 起设计了规则表达式（EL），一切复杂流程都通过 EL 描述。规则写在 `<chain>` 标签内，一个规则文件可包含多个 chain。

```xml
<chain name="chain1">
    THEN(a, b, WHEN(c, d));
</chain>
```

**关键字大小写**：编排关键字 `THEN/WHEN/IF/SWITCH/FOR/WHILE/ITERATOR/CATCH/PRE/FINALLY/AND/OR/NOT/DO/BREAK/DEFAULT/ELSE/ELIF` 必须**大写**；`to`/`TO` 与 `node`/`NODE` 大小写均可。⚠️ 方法类子关键字均为**小写**：`tag/data/bind/id/any/must/percentage/ignoreError/maxWaitSeconds/maxWaitMilliseconds/parallel/retry`（注意 `.retry(3)` 是小写，不是 `RETRY`）。

**分号**：单行表达式可不加分号也能运行；但使用**子变量**（多行表达式）时**必须**每句加分号，否则解析报错。官方建议无论单行多行都在每句表达式后加分号（IDEA 插件会做语法检查，缺分号会标红）。详见第 11 节。

**注释**（v2.13.0+）：只支持 `/** **/`（可多行），**不支持** `//` 单行注释。注释不能夹杂在表达式中间（例如 `THEN(a, b, /** 注释 **/ WHEN(c,d))` 无法编译），只能写在表达式之外或子项整体之前。

---

## 2. 串行编排 THEN

依次执行若干组件，关键字 `THEN` 必须大写。

**语法**：`THEN(a, b, c, d)`

**等价关键字**（v2.11.4+）：`SER` 与 `THEN` 完全等价，写作 `SER(a, b, c, d)`。

**嵌套**等价：`THEN(a, b, THEN(c, d))` ≡ `THEN(a, b, c, d)`。

```xml
<chain name="chain1">
    THEN(a, b, c, d);
</chain>
```

---

## 3. 并行编排 WHEN

并行执行若干组件，关键字 `WHEN` 必须大写。等价关键字 `PAR`（`PAR(a, b, c)`）。

```xml
<chain name="chain1">
    WHEN(a, b, c);
</chain>
```

### 3.1 与串行嵌套

```xml
<chain name="chain1">
    THEN(
        a,
        WHEN(b, c, d),
        e
    );
</chain>
```
b/c/d 默认全部并行执行完毕后才执行 e。

### 3.2 WHEN 的修饰子关键字

| 子关键字 | 版本 | 默认 | 作用 |
|---|---|---|---|
| `ignoreError(true)` | — | false | 任一分支异常仍继续后续节点 |
| `any(true)` | — | false | 任一分支先执行完即忽略其他分支，继续往下 |
| `must(b, c)` / `must(b, "t1")` | v2.11.1+ | — | 指定需等待的节点/表达式（1 个或多个）完成即继续，忽略同级其他任务 |
| `percentage(0.6)` | v2.15.0+ | — | 在全部任务中随机挑 N 个（向上取整），完成即继续 |
| `maxWaitSeconds(n)` / `maxWaitMilliseconds(n)` | v2.11.0+ | — | 并行整体超时控制 |

**ignoreError**：b/c/d 任一异常，e 仍会执行。分支异常**不会向上抛**——WHEN 整体对失败分支完全吞错（仅超时场景打 warn 日志），因此只要后续环节无异常，整个流程 `LiteflowResponse.isSuccess()` 仍为 `true`、`getCause()` 为空（源码 `liteflow-core/.../flow/parallel/strategy/ParallelStrategyExecutor.java:236-252`：ignoreError=true 时跳过所有失败分支的异常抛出）。
```xml
THEN(a, WHEN(b, c, d).ignoreError(true), e);
```

**any**：任一分支先完成即往下走（忽略其他分支）。
```xml
THEN(a, WHEN(b, THEN(c, d), e).any(true), f);
```

**must**（不可为空）：可指定节点，也可指定表达式 id（用引号括起来）。若指定节点率先完成，其余未完成的同级别任务被忽略。
```xml
THEN(a, WHEN(b, c, d).must(b, c), f);

/* 指定嵌套表达式：先给表达式设 id，must 里用引号引用 */
THEN(a, WHEN(b, THEN(c, d).id("t1"), e).must(b, "t1"), f);
```

**percentage**：入参为数值，范围 `[0, 1]`。`0` 等价于 `any(true)`；`1` 相当于不加。例：5 个组件、`percentage(0.6)` 随机挑 3 个；`0.66` 则随机挑 4 个（5×0.66=3.3，向上取整）。
```xml
<chain id="chain1">
    WHEN(a, b, c, d, e).percentage(0.6);
</chain>
```

### 3.3 WHEN 线程池隔离（v2.11.1+）

默认所有 WHEN 共用一个线程池。配置 `liteflow.when-thread-pool-isolate=true` 后，每个 WHEN 拥有独立线程池，可提升复杂嵌套 WHEN 的运行速度并规避部分锁问题。
```properties
liteflow.when-thread-pool-isolate=true
```

---

## 4. 选择编排 SWITCH

根据选择组件的返回值，从多个子项中选一个执行。`SWITCH` 必须大写，`to`/`TO` 大小写均可。

**语法**：`SWITCH(a).to(b, c, d)`

### 4.1 DEFAULT 关键字（v2.9.5+）

`SWITCH...TO...DEFAULT`：当返回值不命中任何子项时，走 DEFAULT。DEFAULT 内也可为表达式。
```xml
<chain name="chain1">
    SWITCH(x).TO(a, b, c).DEFAULT(y);
</chain>
```

### 4.2 选择表达式子项：id 与 tag

`SWITCH` 中若嵌套 `THEN`/`WHEN` 等表达式作为可选项，需给该表达式设置 `id`（或 `tag`），选择组件返回该 id/tag 即可选中整段表达式。

```xml
<chain name="chain1">
    THEN(
        a,
        SWITCH(b).to(
            c,
            THEN(d, e).id("t1")
        ),
        f
    );
</chain>
```
选择组件返回字符串即可：
```java
@LiteflowComponent("b")
public class BCmp extends NodeSwitchComponent {
    @Override
    public String processSwitch() throws Exception {
        return "t1";          // 选中 id="t1" 的 THEN
    }
}
```

用 `tag` 时，选择组件返回 `"tag:t1"` 或 `":t1"` 均可：
```xml
SWITCH(b).to(c, THEN(d, e).tag("t1"))
```
```java
return "tag:t1";   // 或 return ":t1";
```

### 4.3 与 THEN/WHEN 嵌套

```xml
THEN(
    a,
    WHEN(b, SWITCH(c).to(d, e)),
    f
);
```

---

## 5. 条件编排 IF（v2.8.5+）

`IF`/`ELIF` 的第一个参数须为**布尔组件**（返回 boolean）。本质是 if/else。

**二元**：`IF(x, a)` —— x 为真执行 a，为真链路 `x→a`，为假链路 `x→(跳过)`。
```xml
THEN(IF(x, a), b);
```

**三元**：`IF(x, a, b)` —— 真走 a，假走 b。
```xml
THEN(IF(x, a, b), c);
```

**ELSE**：`IF(x, a).ELSE(b)` 等价于 `IF(x, a, b)`。
```xml
IF(x, a).ELSE(b);
```

**ELIF**：用法类似 Java 的 else if，可跟多个，一般末尾接 `ELSE`。
```xml
IF(x1, a).ELIF(x2, b).ELIF(x3, c).ELIF(x4, d).ELSE(THEN(m, n));
```

> 注意一：只有 `IF` 二元表达式后才能接 `ELIF`；三元后接 `ELIF` 会被覆盖（框架虽容错但不推荐）。
> 注意二：多重条件也能用嵌套 `IF` 完成，但官方推荐用 `ELIF` 替代嵌套以提升可读性。

---

## 6. 循环编排（v2.9.0+）

### 6.1 FOR（固定次数）

```xml
/* 直接写次数 */
FOR(5).DO(THEN(a, b));

/* 用次数循环组件，运行时返回 int 次数 */
FOR(f).DO(THEN(a, b));
```
`f` 须为**次数循环组件**。

### 6.2 WHILE（条件循环）

```xml
WHILE(w).DO(THEN(a, b));
```
`w` 须为**布尔组件**，返回 true 则继续循环。

**WHILE(true)**（v2.15.1+）：支持无限循环，但**必须搭配 BREAK**，否则死循环。
```xml
WHILE(true).DO(THEN(a, b)).BREAK(b);
```

### 6.3 ITERATOR（迭代循环）

用于集合循环。`x` 须为**迭代循环组件**，返回一个迭代器。
```xml
ITERATOR(x).DO(THEN(a, b));
```
> 注意：迭代循环组件**只支持 Java 定义，不支持脚本**。

### 6.4 BREAK（退出循环）

`BREAK` 可跟在 `FOR`/`WHILE`/`ITERATOR` 后，**在每次循环末尾判断**。`c` 须为布尔组件，返回 true 则退出循环。
```xml
FOR(f).DO(THEN(a, b)).BREAK(c);
WHILE(w).DO(THEN(a, b)).BREAK(c);
ITERATOR(x).DO(THEN(a, b)).BREAK(c);
```

### 6.5 多层嵌套循环中获取下标（v2.12.3+）

3 层嵌套 `FOR(x).DO(FOR(y).DO(FOR(z).DO(THEN(a,b))))` 中，最内层 a 组件取下标：

| 取哪一层 | API |
|---|---|
| 当前（最内）层 | `this.getLoopIndex()` 或 `this.getPreNLoopIndex(0)` |
| 上一层（第二层） | `this.getPreLoopIndex()` 或 `this.getPreNLoopIndex(1)` |
| 再上一层（第一层） | `this.getPreNLoopIndex(2)` |

`getPreNLoopIndex(n)` 的 `n` 表示**往前**取多少层，`0` 为当前层，依次类推。

### 6.6 多层嵌套循环中获取迭代对象（v2.12.3+）

3 层嵌套 `ITERATOR` 中，最内层 a 取迭代对象：

| 取哪一层 | API |
|---|---|
| 当前层 | `this.getCurrLoopObj()` 或 `this.getPreNLoopObj(0)` |
| 上一层 | `this.getPreLoopObj()` 或 `this.getPreNLoopObj(1)` |
| 再上一层 | `this.getPreNLoopObj(2)` |

> 脚本中获取循环下标/迭代对象：见官方"脚本与 Java 进行交互"文档的"元数据获取方式之二"（以源码/官方文档为准）。

### 6.7 异步循环模式（v2.11.0+）

循环表达式可用 `parallel` 子关键字（默认 false）。设为 `true` 时，**各循环子项之间并行执行**（每个子项内部执行方式不变）。

```xml
FOR(2).parallel(true).DO(THEN(a, b, c));
WHILE(x).parallel(true).DO(THEN(a, b, c));
ITERATOR(x).parallel(true).DO(THEN(a, b, c));
```

要点：
1. `parallel` 只能用于循环表达式（FOR/WHILE/ITERATOR）。
2. 异步模式仍支持 BREAK：退出组件返回 true 时，停止向线程池提交新任务，但已提交任务会继续执行，循环在所有已提交任务执行完毕后退出。
3. 异步循环底层使用线程池（详见官方"组件异步层面的线程池"文档，以源码/官方文档为准）。

---

## 7. 捕获异常表达式 CATCH（v2.10.0+）

用法 `CATCH(...).DO(c)`：被包裹的组件抛异常时执行 c。

```xml
<chain name="chain1">
    CATCH(THEN(a, b)).DO(c);
</chain>
```
- 若 a 抛异常，b 不执行，直接执行 c。
- 在 c 中通过 `this.getSlot().getException()` 获取异常。
- 用了 `CATCH` 后，即使内部抛异常，整个流程 `LiteflowResponse.isSuccess()` 仍为 `true`，`getCause()` 无 Exception（因为异常已被自行处理）。

**CATCH 也可不加 DO**：仅吞掉异常。
```xml
THEN(CATCH(THEN(a, b)), c);
```
无论 a/b 是否抛异常，c 总会执行；若 a 抛异常，最终链路为 `a==>c`。

**搭配循环实现 continue 效果**：在循环体内 `CATCH` 包裹，组件中按条件往外抛异常即可跳过本次后续步骤、继续下一轮。
```xml
FOR(x).DO(CATCH(THEN(a, b, c)));
```

---

## 8. 与或非表达式 AND / OR / NOT（v2.10.2+）

用于把多个布尔组件/与或非表达式组合成一个布尔值，可用在所有"返回布尔值"的位置（`IF`、`WHILE`、`BREAK`）。

| 关键字 | 含义 | 参数 |
|---|---|---|
| `AND(x, y, ...)` | 全真为真 | 多个布尔组件/与或非表达式 |
| `OR(x, y, ...)` | 任一真即真 | 多个布尔组件/与或非表达式 |
| `NOT(x)` | 取反 | **只能有一个**布尔组件/与或非表达式 |

```xml
IF(AND(x, y), a, b);          /* x 与 y 同真走 a */
IF(OR(x, y), a, b);           /* x 或 y 真 走 a */
IF(NOT(x), a, b);             /* x 假 走 a */
```

**复杂嵌套**：
```xml
IF(
    OR(AND(x1, x3), NOT(OR(x3, x4))),
    a, b
);
```

> 注意：在 `THEN` 中使用与或非表达式会报错（普通组件不返回布尔值）。

---

## 9. 子流程 / 子变量

### 9.1 使用子流程

一个 chain 可以直接引用另一个 chain 的 id 作为编排单元，把复杂流程拆分：

```xml
<chain name="mainChain">
    THEN(A, B, WHEN(chain1, D, chain2), SWITCH(X).to(M, N, chain3), Z);
</chain>

<chain name="chain1"> THEN(C, WHEN(J, K)); </chain>
<chain name="chain2"> THEN(H, I); </chain>
<chain name="chain3"> WHEN(Q, THEN(P, R)).id("w01"); </chain>
```

### 9.2 使用子变量（let 形式）

在同一个 `<chain>` 内用 `变量名 = 表达式;` 定义子变量，再在主表达式中引用。**子变量定义语句必须以分号结尾**。

```xml
<chain>
    t1 = THEN(C, WHEN(J, K));
    w1 = WHEN(Q, THEN(P, R)).id("w01");
    t2 = THEN(H, I);

    THEN(A, B, WHEN(t1, D, t2), SWITCH(X).to(M, N, w1), Z);
</chain>
```

子变量让复杂编排更易读，且能在该 chain 内复用。

---

## 10. 前置 PRE / 后置 FINALLY

针对整个链路，在链路之前/之后固定执行某些组件（均为串行节点，目前不支持异步）。

**前置**：`PRE(...)`，固定在流程开始前执行。
```xml
THEN(PRE(p1, p2), a, b, c, WHEN(d, e));
```

**后置**：`FINALLY(...)`，固定在流程结束后执行，**不受 Exception 影响**，即便节点出错也会执行。
```xml
THEN(a, b, c, FINALLY(f1, f2));
```

**顺序**：`PRE`/`FINALLY` 可写在任意位置，效果一致：
```xml
THEN(FINALLY(f1, f2), c, PRE(a), d);   /* 等价于 PRE 在前、FINALLY 在后 */
```

**层级和范围**（v2.9.5+ 起支持任意层级）：可写在子流程、子变量中。下例最终执行结果为 `p1==>p2==>p1==>p2==>a==>b==>c==>f1==>f2==>f1`：
```xml
<chain name="chain6">
    c1 = THEN(PRE(p1, p2), THEN(a, b, c), FINALLY(f1, f2));
    THEN(PRE(p1, p2), c1, FINALLY(f1));
</chain>
```

> 注意：`PRE`/`FINALLY` **只能写在 `THEN` 表达式中**。写在 `WHEN`/`SWITCH`/`IF` 等中不生效且毫无意义。

---

## 11. 组件参数语法（tag / data / bind）

给编排中的组件（或表达式/子变量/chain）设置运行时参数，在组件内取出参与逻辑。

### 11.1 tag

两种用途：① 给 `SWITCH` 提供选择标签（见第 4 节）；② 赋值，组件内用 `this.getTag()` 取出。同一组件可按不同 tag 编排多次：
```xml
THEN(a.tag("1"), a.tag("2"), a.tag("3"));
```
```java
String tag = this.getTag();
```

### 11.2 data（v2.9.0+）

通过 `data` 设置外置参数，建议 JSON 格式。可在不同 chain 给同一组件赋不同值。
```xml
<chain name="chain1">
    cmpData = '{"name":"jack","age":27,"birth":"1995-10-01"}';
    THEN(a, b.data(cmpData), c);
</chain>
```
组件内取出（传入 class 可直接转成对应 Java 对象）：
```java
User user = this.getCmpData(User.class);
```
若 data 是 JSON 数组，用 `getCmpDataList(...)` 获取。

`data` 也可作用于**表达式/子变量/chain**：被赋值的单元内**所有组件**都设置相同的值。
```xml
THEN(a, b, c).data("123");
```

### 11.3 bind（v2.13.0+）

#### 绑定静态数据（KV）
```xml
THEN(a.bind("k1", "test"), b);
```
```java
String v = this.getBindData("k1", String.class);
```
value 为 JSON 字符串时，第二个参数传 VO 的 class，LiteFlow 自动转型。同样可作用于表达式/子变量/chain（其内所有组件绑定相同值）。

#### 绑定动态数据（tag/data 做不到）
value 必须为 `${表达式}` 形式，LiteFlow 会到上下文中按表达式搜索取值。

上下文：
```java
public class OrderContext {
    private Integer id;
    private String orderCode;
    private Member member;
    // getter/setter 省略
}
public class Member {
    private String memberCode;
    private String memberName;
    // getter/setter 省略
}
```
```xml
THEN(a, b.bind("k1", "${orderCode}"))                /* 取 orderCode */
THEN(a, b.bind("k1", "${member.memberName}"))        /* 点操作符取嵌套属性 */
```

**多上下文同名属性**：不指定时永远 bind 第一个匹配上下文的属性；需指定时用"类名首字母小写"作前缀：
```xml
THEN(a, b.bind("k1", "${userContext.id}"))
```
类名前缀可通过 `@ContextBean("userCx")` 自定义：
```java
@ContextBean("userCx")
public class UserContext { ... }
```
```xml
THEN(a, b.bind("k1", "${userCx.id}"))
```
> 官方建议：多上下文属性名不冲突时，不要指定上下文，直接智能匹配。

#### bind 覆盖用法（v2.13.1+）
节点和表达式同时 bind 同一个 key 时**不互相覆盖**：
```xml
THEN(a, b.bind("k","v1"), c).bind("k", "v2");
/* a→v2, b→v1, c→v2 */
```
若要强制覆盖所有节点，给表达式层 bind 传第三个参数 `true`：
```xml
THEN(a, b.bind("k","v1"), c).bind("k", "v2", true);
/* a,b,c 全为 v2 */
```

---

## 12. 重试 retry（v2.12.0+）

在 EL 层设置失败重试。

**单组件**：
```xml
THEN(a, b.retry(3));
```
b 抛任何异常时最多重试 3 次；任一次成功即继续；3 次都失败则中断，`LiteflowResponse.isSuccess()` 为 false 并带具体异常。

**表达式 / 子变量**：
```xml
THEN(a, b).retry(3);
FOR(c).DO(a).retry(3);

exp = SWITCH(x).to(m, n, p);
IF(f, exp.retry(3), b);
```

**整个 chain**：
```xml
<chain id="sub"> THEN(a, b); </chain>
<chain id="main"> WHEN(x, y, sub.retry(3)); </chain>
```

**指定异常**（可多个，全限定类名字符串）：仅当抛出指定异常之一才重试，其余异常直接中断。
```xml
THEN(a, b).retry(3, "java.lang.NullPointerException");
THEN(a, b).retry(3,
    "java.lang.NullPointerException",
    "java.lang.ArrayIndexOutOfBoundsException");
```

**特例**：组件内 `this.setIsEnd(true)` 抛出的 `ChainEndException` 永远不会触发重试（强制中止，不应被重试）。

---

## 13. 超时控制（v2.11.0+）

用 `maxWaitSeconds(n)`（秒，int）或 `maxWaitMilliseconds(n)`（毫秒，int）对任意**组件、表达式、流程**做超时控制。

```xml
<!-- 串行/并行/循环/选择/条件 -->
THEN(a, b).maxWaitSeconds(5);
WHEN(a, b).maxWaitSeconds(3);
FOR(2).DO(a).maxWaitSeconds(3);
WHILE(w).DO(a).maxWaitSeconds(3);
ITERATOR(x).DO(a).maxWaitSeconds(3);
SWITCH(s).TO(a, b).maxWaitSeconds(3);
IF(f, b, c).maxWaitSeconds(3);

<!-- 组件级 -->
WHEN(a.maxWaitSeconds(2), b.maxWaitSeconds(3));

<!-- chain 级 -->
<chain name="testChain"> THEN(b); </chain>
<chain name="chain"> testChain.maxWaitSeconds(3); </chain>
```

**注意事项**：
1. `FINALLY` **不可**使用该关键字（`FINALLY(b).maxWaitSeconds(3)` 不被允许）。
2. 若 `THEN` 设了超时，其**直属**的 `FINALLY` 不受超时控制；但若 `FINALLY` 不是该 `THEN` 直属（如嵌套在更深层级），仍受超时控制。
3. 除 `WHEN` 外，`maxWaitSeconds` 必须放在**完整语义的最后**：
   ```xml
   FOR(5).DO(THEN(e, f)).maxWaitSeconds(5);   /* 正确 */
   FOR(5).maxWaitSeconds(5).DO(THEN(e, f));   /* 错误 */
   ```
   而 `WHEN` 允许不放在最后：
   ```xml
   WHEN(a, b).maxWaitSeconds(5).any(true);    /* 允许 */
   ```

---

## 14. 链路继承（v2.12.0+，Beta 实验性）

chain 之间可继承扩展。子 chain 用 `extends` 属性声明父 chain；父 chain 中用 `{{占位符}}` 预留扩展点，子 chain 中用 `{{占位符}}=表达式` 实现（实现可为组件/表达式/chain id，最终须为合法 EL）。

```xml
<chain id="base">
    THEN(a, b, {{0}}, {{1}});
</chain>

<chain id="implA" extends="base">
    {{0}}=IF(c, d, e);
    {{1}}=SWITCH(f).to(j, k);
</chain>
```
等价于：
```xml
<chain id="implA">
    THEN(a, b, IF(c, d, e), SWITCH(f).to(j, k));
</chain>
```

**多级继承**：子 chain 实现中可继续包含占位符，形成多级链。
```xml
<chain id="base">    THEN(a, b, {{0}}, {{1}}); </chain>
<chain id="base2" extends="base">
    {{0}}=THEN(a, b, {{3}});
    {{1}}=SWITCH(f).to({{4}}, k);
</chain>
<chain id="implB" extends="base2">
    {{3}}=THEN(a, b);
    {{4}}=j;
</chain>
```

**注意事项**：
- 占位符必须是 `{{..}}` 双花括弧（避免与用户自定义占位符冲突）；`{{x}}` 中 `x` 可为纯数字，或"字母/下划线/数字构成但数字不能开头"。合法：`{{1}}`、`{{a}}`、`{{a1}}`、`{{a_1}}`；非法：`{{1a}}`、`{{1_a}}`。
- 被继承 chain 至少要有 1 个占位符，且所有占位符必须在子 chain 中全部实现，否则抛异常。
- `{{a}}=THEN(x,y,z)` 必须写成**一行**，多行会报错。
- 含未实现占位符的 chain（如上例 base/base2）直接执行会抛异常。
- 子 chain 中除占位符实现以外的表达式会被忽略。

---

## 15. 验证规则（v2.9.4+）

验证一段 EL 能否被正确解析：

```java
boolean isValid = LiteFlowChainELBuilder.validate("THEN(a, b, h)");
```

带异常信息的验证（v2.12.2+）：
```java
ValidationResp resp = LiteFlowChainELBuilder.validateWithEx("THEN(a, b, h)");
if (!resp.isSuccess()) {
    log.error(resp.getCause());
}
```

---

## 16. 组件名包装 node

组件名规范：不能以数字开头，中间不能有运算符号（如 `88Cmp`、`cmp-11`、`user=123` 非法，启动时报错）。若需要用任意形式的组件名（如自动生成），用 `node` 关键字包装：

```xml
THEN(a, b, node("88Cmp"), node("cmp-11"));
```
`a` 与 `node("a")` 等价。

---

## 17. 复杂编排例子（综合）

### 例子一（含 SWITCH 套 THEN/WHEN）

```xml
<chain name="chain1">
    THEN(
        A,
        WHEN(
            THEN(B, C),
            THEN(D, E, F),
            THEN(
                SWITCH(G).to(
                    THEN(H, I, WHEN(J, K)).id("t1"),
                    THEN(L, M).id("t2")
                ),
                N
            )
        ),
        Z
    );
</chain>
```
用子变量优化：
```xml
<chain name="chain1">
    item1   = THEN(B, C);
    item2   = THEN(D, E, F);
    item3_1 = THEN(H, I, WHEN(J, K)).id("t1");
    item3_2 = THEN(L, M).id("t2");
    item3   = THEN(SWITCH(G).to(item3_1, item3_2), N);

    THEN(A, WHEN(item1, item2, item3), Z);
</chain>
```

### 例子二（巨复杂，强烈建议拆子变量）

```xml
<chain name="chain1">
    item1 = THEN(D, E, F).id("t1");

    item2_1 = THEN(
        SWITCH(G).to(THEN(H, I).id("t2"), J),
        K
    );
    item2_2 = THEN(L, M);
    item2   = THEN(C, WHEN(item2_1, item2_2)).id("t3");

    THEN(A, SWITCH(B).to(item1, item2), Z);
</chain>
```
> 上述两例可在源码测试用例中找到：`com.yomahub.liteflow.test.complex.ComplexELSpringbootTest1` / `ComplexELSpringbootTest2`。

**原则**：努力让规则最大化简化；复杂编排用子流程或子变量拆分，提升可读性。

---

## 18. 算子速查表

| 算子/关键字 | 语义 | 版本 | 备注 |
|---|---|---|---|
| `THEN(...)` / `SER(...)` | 串行 | SER v2.11.4+ | 大写；可嵌套 |
| `WHEN(...)` / `PAR(...)` | 并行 | — | 大写 |
| `.ignoreError(true)` | 忽略错误 | — | WHEN 子关键字 |
| `.any(true)` | 任一完成即继续 | — | WHEN 子关键字 |
| `.must(...)` | 指定完成即继续 | v2.11.1+ | WHEN 子关键字，不可空，id 需引号 |
| `.percentage(n)` | 随机 N 个完成即继续 | v2.15.0+ | WHEN 子关键字，n∈[0,1] |
| `SWITCH(x).to(...)` / `.TO(...)` | 选择 | — | to 大小写均可 |
| `.DEFAULT(y)` | 选择默认 | v2.9.5+ | SWITCH 后 |
| `IF(x, a)` / `IF(x, a, b)` | 条件 | v2.8.5+ | x 须为布尔组件 |
| `.ELSE(b)` / `.ELIF(x, b)` | 否则/否则如果 | — | 接 IF 二元后 |
| `FOR(n\|f).DO(...)` | 次数循环 | v2.9.0+ | f 为次数循环组件 |
| `WHILE(w).DO(...)` | 条件循环 | v2.9.0+ | w 为布尔组件 |
| `WHILE(true).DO(...)` | 无限循环 | v2.15.1+ | 必须配 BREAK |
| `ITERATOR(x).DO(...)` | 迭代循环 | v2.9.0+ | 仅 Java，不支持脚本 |
| `.BREAK(c)` | 退出循环 | v2.9.0+ | 每轮末尾判断；c 为布尔组件 |
| `.parallel(true)` | 异步循环 | v2.11.0+ | 循环子项并行 |
| `CATCH(...).DO(c)` | 捕获异常 | v2.10.0+ | DO 可省 |
| `AND(...)` / `OR(...)` / `NOT(x)` | 与/或/非 | v2.10.2+ | 用于 IF/WHILE/BREAK；NOT 仅一个参数 |
| `PRE(...)` / `FINALLY(...)` | 前置/后置 | 任意层级 v2.9.5+ | 仅在 THEN 中；FINALLY 不受异常影响 |
| `.tag("...")` | 标签 | — | `this.getTag()`；也可用于 SWITCH 选择 |
| `.data(...)` | 外置参数 | v2.9.0+ | `this.getCmpData(class)`；建议 JSON |
| `.bind(k, v)` | 绑定 KV | v2.13.0+ | `this.getBindData(k, class)`；支持动态 `${...}` |
| `.bind(k, v, true)` | bind 强制覆盖 | v2.13.1+ | 覆盖表达式内所有节点 |
| `.retry(n[, ex...])` | 重试 | v2.12.0+ | 可指定异常全限定类名 |
| `.maxWaitSeconds(n)` / `.maxWaitMilliseconds(n)` | 超时 | v2.11.0+ | 多数须放语义末尾；FINALLY 不可用 |
| `.id("...")` | 表达式 id | — | 供 SWITCH/must 选择 |
| `node("...")` | 组件名包装 | — | 支持任意形式组件名 |
| `extends="..."` + `{{x}}` | 链路继承 | v2.12.0+ Beta | 占位符双花括弧 |

---

## 19. 常见坑 / 注意

- **分号**：单行表达式可不加分号；但**子变量定义**（`t1 = THEN(...)`）属多行语句，**必须加分号**，否则解析报错。官方建议每句都加。IDEA 插件会做缺分号红波浪线提示。
- **注释**（v2.13.0+）：仅支持 `/** **/`，不支持 `//`；不能夹在任意两个子项之间（如 `THEN(a, /** x **/ b)` 无法编译），只能写在某表达式内容**最开头**（第一个子项之前）或表达式之外。
- **关键字大小写**：编排关键字 `THEN/WHEN/IF/SWITCH/FOR/WHILE/ITERATOR/CATCH/PRE/FINALLY/AND/OR/NOT/DO/BREAK/DEFAULT/ELSE/ELIF` 必须**大写**；`to`/`TO`、`node`/`NODE` 大小写均可；方法类子关键字（`tag/data/bind/id/any/must/percentage/ignoreError/maxWaitSeconds/maxWaitMilliseconds/parallel/retry`）均为**小写**——⚠️ `.retry(3)` 是小写，写成 `RETRY` 会解析失败。
- **组件名规范**：不能数字开头、不能含运算符；需要不规范名时必须用 `node("...")` 包装，否则启动报错。
- **PRE/FINALLY 范围**：只能写在 `THEN` 中；写在 WHEN/SWITCH/IF 中不生效且无意义。FINALLY 不受异常影响、总会执行。
- **maxWaitSeconds 位置**：除 WHEN 外必须放在完整语义最后（`FOR(5).DO(...).maxWaitSeconds(5)` 才对）；`FINALLY` 不可用 maxWaitSeconds；THEN 直属的 FINALLY 不受其超时控制。
- **WHILE(true)**：必须搭配 BREAK，否则死循环。
- **ITERATOR 组件**：只支持 Java 定义，不支持脚本。
- **BREAK 判断时机**：在每次循环**末尾**判断（不是开头）。
- **IF 后接 ELIF**：只有 IF 二元表达式可接 ELIF；三元后接 ELIF 会被覆盖（虽容错但不推荐）。
- **CATCH 吞异常**：用了 CATCH 后 `LiteflowResponse.isSuccess()` 仍为 true、`getCause()` 无异常——因为异常已被自行处理，不要再依赖响应的 isSuccess 判断内部是否出错。
- **retry 与 setIsEnd**：组件内 `this.setIsEnd(true)` 抛出的 `ChainEndException` 永不触发重试。
- **bind 多上下文同名属性**：不指定上下文时永远 bind 第一个匹配上下文；需明确时用"类名首字母小写"前缀（或 `@ContextBean("别名")` 自定义前缀）。属性名不冲突时官方建议不指定、智能匹配。
- **链路继承占位符**：必须双花括弧 `{{x}}`；`x` 数字不能开头；占位符实现 `{{a}}=...` 必须写一行；含未实现占位符的 chain 直接执行会抛异常；子 chain 中除占位符实现外的表达式会被忽略。该特性为 **Beta**。
- **must 引用嵌套表达式**：需先给嵌套表达式设 `.id("...")`，在 must 中用**引号**括起该 id。
- **percentage**：值域 `[0,1]`；`0` 等价 `any(true)`，`1` 等于不加；按向上取整挑选任务数。
- **验证**：上线前可用 `LiteFlowChainELBuilder.validate(el)` 或 `validateWithEx(el)` 校验 EL 是否合法。
