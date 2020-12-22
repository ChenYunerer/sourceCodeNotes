---
title: Mybatis-Plus分页
tags: Mybatis
categories: Spring&SpringCloud
---

# Mybatis-Plus分页

源码基于：mybatis-plus 3.4.1

## PaginationInterceptor

```java
@Intercepts({@Signature(type = StatementHandler.class, method = "prepare", args = {Connection.class, Integer.class})})
public class PaginationInterceptor extends AbstractSqlParserHandler implements Interceptor {
  ......
}

```

继承Interceptor通过@Intercepts拦截StatementHandler的prepare

```java
PaginationInterceptor.class
@Override
public Object intercept(Invocation invocation) throws Throwable {
    StatementHandler statementHandler = PluginUtils.realTarget(invocation.getTarget());
    MetaObject metaObject = SystemMetaObject.forObject(statementHandler);

    // SQL 解析
    this.sqlParser(metaObject);

    // 先判断是不是SELECT操作  (2019-04-10 00:37:31 跳过存储过程)
    MappedStatement mappedStatement = (MappedStatement) metaObject.getValue("delegate.mappedStatement");
    if (SqlCommandType.SELECT != mappedStatement.getSqlCommandType()
        || StatementType.CALLABLE == mappedStatement.getStatementType()) {
        return invocation.proceed();
    }

    // 针对定义了rowBounds，做为mapper接口方法的参数
    BoundSql boundSql = (BoundSql) metaObject.getValue("delegate.boundSql");
    Object paramObj = boundSql.getParameterObject();

    // 判断参数里是否有page对象
    IPage<?> page = ParameterUtils.findPage(paramObj).orElse(null);

    /*
     * 不需要分页的场合，如果 size 小于 0 返回结果集
     */
    if (null == page || page.getSize() < 0) {
        return invocation.proceed();
    }

    if (this.limit > 0 && this.limit <= page.getSize()) {
        //处理单页条数限制
        handlerLimit(page);
    }

    String originalSql = boundSql.getSql();
    Connection connection = (Connection) invocation.getArgs()[0];

    if (page.isSearchCount() && !page.isHitCount()) {
      	//生成查询总数的sql
        SqlInfo sqlInfo = SqlParserUtils.getOptimizeCountSql(page.optimizeCountSql(), countSqlParser, originalSql, metaObject);
      	//查询数据总数，保存在page中
        this.queryTotal(sqlInfo.getSql(), mappedStatement, boundSql, page, connection);
        if (!this.continueLimit(page)) {
            return null;
        }
    }
  	//获取数据库类型
    DbType dbType = this.dbType == null ? JdbcUtils.getDbType(connection.getMetaData().getURL()) : this.dbType;
 		//获取数据库方言
    IDialect dialect = Optional.ofNullable(this.dialect).orElseGet(() -> DialectFactory.getDialect(dbType));
  	//对orderby做处理
    String buildSql = concatOrderBy(originalSql, page);
  	//通过数据库方言生成分页查询sql保存在DialectModel
    DialectModel model = dialect.buildPaginationSql(buildSql, page.offset(), page.getSize());
    Configuration configuration = mappedStatement.getConfiguration();
    List<ParameterMapping> mappings = new ArrayList<>(boundSql.getParameterMappings());
    Map<String, Object> additionalParameters = (Map<String, Object>) metaObject.getValue("delegate.boundSql.additionalParameters");
    model.consumers(mappings, configuration, additionalParameters);
    metaObject.setValue("delegate.boundSql.sql", model.getDialectSql());
    metaObject.setValue("delegate.boundSql.parameterMappings", mappings);
    return invocation.proceed();
}
```

