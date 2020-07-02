## Mybatis源码分析

---

### MybatisAutoConfigurationg构建SqlSessionFactory：

通过SqlSessionFactoryBean构建SqlSessionFactory，构建过程中：

1.构建configuration，通过MybatisProperties对SqlSessionFactoryBean进行赋值，接下来构建SqlSessionFactory

2.通过XMLConfigBuilder解析配置文件

3.对configuration对象再做处理，配置typeAliasPackage、typeAlias、plugin、typeHandlersPackage、typeHandlers、databaseIdProvider、cache

4.通过XMLMapperBuilder对每个Mapper XML进行解析

5.最后通过以上的所有步骤产生的configuration去构建最后的SqlSessionFactory

### MybatisAutoConfigurationg构建SqlSessionTemplate：

通过sqlSessionFactory构建SqlSessionTemplate

--------

### XMLConfigBuilder解析配置文件

