---
title: Mybatis源码分析
---



## Mybatis源码分析

---

### MybatisAutoConfigurationg构建SqlSessionFactory：

通过SqlSessionFactoryBean构建SqlSessionFactory，构建过程中：

1. 构建configuration，通过MybatisProperties对SqlSessionFactoryBean进行赋值，接下来构建SqlSessionFactory
2. 通过XMLConfigBuilder解析配置文件
3. 对configuration对象再做处理，配置typeAlias、plugin、typeHandlersPackage、typeHandlers、databaseIdProvider、cache
4. 设置默认的transactionFactory为SpringManagedTransactionFactory
5. 设置Environment(environment(SqlSessionFactoryBean.class.getSimpleName)， transactionFactory， dataSource)
6. 通过XMLMapperBuilder对每个Mapper XML进行解析
7. 最后通过以上的所有步骤产生的configuration去构建最后的SqlSessionFactory

### MybatisAutoConfigurationg构建SqlSessionTemplate：

通过sqlSessionFactory构建SqlSessionTemplate

--------

### TypeAliasRegistry

维护Map<String, Class<?>> TYPE_ALIASES，key 是 别名 value 是 Type Class，默认存在一些基础类型以及其包装类的别名

registerAliases方法通过对typeAliasesPackage解析，往TYPE_ALIASES塞值

### InterceptorChain

维护List<Interceptor> interceptors

addInterceptor方法往interceptors添加拦截器

### TypeHandlerRegistry

维护Map<Type, Map<JdbcType, TypeHandler<?>>> TYPE_HANDLER_MAP，默认存在基础类型的TypeHandler

### databaseIdProvider

通过DataSource获取connection，通过connection.getMetaData获取DatabaseProductName

为configure设置databaseId，用以处理针对不同厂商的sql语句

### MapperXML解析

对xml各个标签进行解析，最终构建MappedStatement由configuration维护：Map<String, MappedStatement> mappedStatements

```java
public void parseStatementNode() {
  //以下获取各种参数
  String id = context.getStringAttribute("id");
  String databaseId = context.getStringAttribute("databaseId");

  if (!databaseIdMatchesCurrent(id, databaseId, this.requiredDatabaseId)) {
    return;
  }

  Integer fetchSize = context.getIntAttribute("fetchSize");
  Integer timeout = context.getIntAttribute("timeout");
  String parameterMap = context.getStringAttribute("parameterMap");
  String parameterType = context.getStringAttribute("parameterType");
  Class<?> parameterTypeClass = resolveClass(parameterType);
  String resultMap = context.getStringAttribute("resultMap");
  String resultType = context.getStringAttribute("resultType");
  String lang = context.getStringAttribute("lang");
  LanguageDriver langDriver = getLanguageDriver(lang);

  Class<?> resultTypeClass = resolveClass(resultType);
  String resultSetType = context.getStringAttribute("resultSetType");
  StatementType statementType = StatementType.valueOf(context.getStringAttribute("statementType", StatementType.PREPARED.toString()));
  ResultSetType resultSetTypeEnum = resolveResultSetType(resultSetType);

  String nodeName = context.getNode().getNodeName();
  SqlCommandType sqlCommandType = SqlCommandType.valueOf(nodeName.toUpperCase(Locale.ENGLISH));
  boolean isSelect = sqlCommandType == SqlCommandType.SELECT;
  boolean flushCache = context.getBooleanAttribute("flushCache", !isSelect);
  //select语句默认使用cache
  boolean useCache = context.getBooleanAttribute("useCache", isSelect);
  boolean resultOrdered = context.getBooleanAttribute("resultOrdered", false);

  //引入sql片段构成完整的sql语句
  // Include Fragments before parsing
  XMLIncludeTransformer includeParser = new XMLIncludeTransformer(configuration, builderAssistant);
  includeParser.applyIncludes(context.getNode());

  // Parse selectKey after includes and remove them.
  processSelectKeyNodes(id, parameterTypeClass, langDriver);
  
  //构建sqlSource 此方法中会对#{}进行处理，使用对应的handler对各种动态sql进行处理
  // Parse the SQL (pre: <selectKey> and <include> were parsed and removed)
  SqlSource sqlSource = langDriver.createSqlSource(configuration, context, parameterTypeClass);
  String resultSets = context.getStringAttribute("resultSets");
  String keyProperty = context.getStringAttribute("keyProperty");
  String keyColumn = context.getStringAttribute("keyColumn");
  
  //主键生成器
  KeyGenerator keyGenerator;
  String keyStatementId = id + SelectKeyGenerator.SELECT_KEY_SUFFIX;
  keyStatementId = builderAssistant.applyCurrentNamespace(keyStatementId, true);
  if (configuration.hasKeyGenerator(keyStatementId)) {
    keyGenerator = configuration.getKeyGenerator(keyStatementId);
  } else {
    keyGenerator = context.getBooleanAttribute("useGeneratedKeys",
        configuration.isUseGeneratedKeys() && SqlCommandType.INSERT.equals(sqlCommandType))
        ? Jdbc3KeyGenerator.INSTANCE : NoKeyGenerator.INSTANCE;
  }
  //构建statementBuilder，并且交由configuration维护
  builderAssistant.addMappedStatement(id, sqlSource, statementType, sqlCommandType,
      fetchSize, timeout, parameterMap, parameterTypeClass, resultMap, resultTypeClass,
      resultSetTypeEnum, flushCache, useCache, resultOrdered, 
      keyGenerator, keyProperty, keyColumn, databaseId, langDriver, resultSets);
}
```

MapperXML解析完成后，构建对应的Mapper的MapperProxyFactory由MapperProxyFactory进行维护
```java
XMLMapperBuilder.class
private void bindMapperForNamespace() {
  String namespace = builderAssistant.getCurrentNamespace();
  if (namespace != null) {
    Class<?> boundType = null;
    try {
      boundType = Resources.classForName(namespace);
    } catch (ClassNotFoundException e) {
      //ignore, bound type is not required
    }
    if (boundType != null) {
      if (!configuration.hasMapper(boundType)) {
        // Spring may not know the real resource name so we set a flag
        // to prevent loading again this resource from the mapper interface
        // look at MapperAnnotationBuilder#loadXmlResource
        configuration.addLoadedResource("namespace:" + namespace);
        //调用configuration的addMapper方法添加mapper，实际由configuration中的MapperRegistry来进行处理
        configuration.addMapper(boundType);
      }
    }
  }
}
```

```java
MapperRegistry.class
public <T> void addMapper(Class<T> type) {
  if (type.isInterface()) {
    if (hasMapper(type)) {
      throw new BindingException("Type " + type + " is already known to the MapperRegistry.");
    }
    boolean loadCompleted = false;
    try {
      //构建MapperProxyFactory
      knownMappers.put(type, new MapperProxyFactory<T>(type));
      // It's important that the type is added before the parser is run
      // otherwise the binding may automatically be attempted by the
      // mapper parser. If the type is already known, it won't try.
      MapperAnnotationBuilder parser = new MapperAnnotationBuilder(config, type);
      parser.parse();
      loadCompleted = true;
    } finally {
      if (!loadCompleted) {
        knownMappers.remove(type);
      }
    }
  }
}
```

### AutoConfiguredMapperScannerRegistrar

扫描多有Mapper注解标注的接口，为对应接口的BeanDifinition设置BeanClass为mapperFactoryBean。

在注入对应Mapper对象的时候，通过MapperFactoryBean获取对应Mapper Interface的MapperProxyFactory，

通过MapperProxyFactory构建MapperProxy

```java
ClassPathMapperScanner.class
private void processBeanDefinitions(Set<BeanDefinitionHolder> beanDefinitions) {
  GenericBeanDefinition definition;
  for (BeanDefinitionHolder holder : beanDefinitions) {
    ...
    //设置BeanClass为mapperFactoryBean
    definition.setBeanClass(this.mapperFactoryBean.getClass());
    ...
    }
  }
}
```

```java
MapperFactoryBean.class
@Override
public T getObject() throws Exception {
	//MapperFactoryBean在构建对象时，调用SqlSession的getMapper获取对象
  //SqlSession的getMapper又通过configuration获的getMapper获取对象
  //configuration获的getMapper又通过mapperRegistry的getMapper获取对象
  return getSqlSession().getMapper(this.mapperInterface);
}
```

```java
MapperRegistry.class
public <T> T getMapper(Class<T> type, SqlSession sqlSession) {
  //获取MapperProxyFactory
  final MapperProxyFactory<T> mapperProxyFactory = (MapperProxyFactory<T>) knownMappers.get(type);
  if (mapperProxyFactory == null) {
    throw new BindingException("Type " + type + " is not known to the MapperRegistry.");
  }
  try {
    //构建MapperProxy JAVA动态代理对象
    return mapperProxyFactory.newInstance(sqlSession);
  } catch (Exception e) {
    throw new BindingException("Error getting mapper instance. Cause: " + e, e);
  }
}
```

### Mapper Interface方法调用分析（sql执行流程分析）

根据以上说明，注入的Mapper对象其实是对应的apperProxy也就是其动态代理对象，其中invoke方法的调用主要调用了MapperMethod的execute方法

```java
MapperMethod.class
public Object execute(SqlSession sqlSession, Object[] args) {
  Object result;
  switch (command.getType()) {
    case INSERT: {
    Object param = method.convertArgsToSqlCommandParam(args);
      result = rowCountResult(sqlSession.insert(command.getName(), param));
      break;
    }
    case UPDATE: {
      Object param = method.convertArgsToSqlCommandParam(args);
      result = rowCountResult(sqlSession.update(command.getName(), param));
      break;
    }
    case DELETE: {
      Object param = method.convertArgsToSqlCommandParam(args);
      result = rowCountResult(sqlSession.delete(command.getName(), param));
      break;
    }
    case SELECT:
      if (method.returnsVoid() && method.hasResultHandler()) {
        executeWithResultHandler(sqlSession, args);
        result = null;
      } else if (method.returnsMany()) {
        result = executeForMany(sqlSession, args);
      } else if (method.returnsMap()) {
        result = executeForMap(sqlSession, args);
      } else if (method.returnsCursor()) {
        result = executeForCursor(sqlSession, args);
      } else {
        Object param = method.convertArgsToSqlCommandParam(args);
        result = sqlSession.selectOne(command.getName(), param);
      }
      break;
    case FLUSH:
      result = sqlSession.flushStatements();
      break;
    default:
      throw new BindingException("Unknown execution method for: " + command.getName());
  }
  if (result == null && method.getReturnType().isPrimitive() && !method.returnsVoid()) {
    throw new BindingException("Mapper method '" + command.getName() 
        + " attempted to return null from a method with a primitive return type (" + method.getReturnType() + ").");
  }
  return result;
}
```