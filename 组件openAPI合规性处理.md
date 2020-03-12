## 组件OpenAPI合规性处理

### Swagger以及参数配置

具体参考SwaggerConfig

```java
package com.hikvision.ccms.start.swagger;

import com.google.common.base.Predicates;
import com.google.common.collect.Sets;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;
import springfox.documentation.builders.ApiInfoBuilder;
import springfox.documentation.builders.ParameterBuilder;
import springfox.documentation.builders.PathSelectors;
import springfox.documentation.builders.RequestHandlerSelectors;
import springfox.documentation.builders.ResponseMessageBuilder;
import springfox.documentation.schema.ModelRef;
import springfox.documentation.service.AllowableRangeValues;
import springfox.documentation.service.ApiInfo;
import springfox.documentation.service.Contact;
import springfox.documentation.service.Parameter;
import springfox.documentation.service.ResponseMessage;
import springfox.documentation.spi.DocumentationType;
import springfox.documentation.spring.web.paths.RelativePathProvider;
import springfox.documentation.spring.web.plugins.Docket;
import springfox.documentation.swagger2.annotations.EnableSwagger2;

import javax.servlet.ServletContext;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import static springfox.documentation.builders.PathSelectors.ant;

/**
 * swagger2配置
 */
@Configuration
@EnableSwagger2
@ConditionalOnExpression("${seashell.swagger.enable:false}==true")
public class SwaggerConfig implements WebMvcConfigurer {

	@Value("${component.id:}")
	private String componentId;

	@Value("${component.segment.id:}")
	private String segmentId;

	@Value("${component.name:}")
	private String componentName;

	@Value("${component.version:}")
	private String componentVersion;

	@Value("${component.se.name:}")
	private String componentSEName;

	/**
	 * 组件内部接口swagger
	 */
	@Bean
	public Docket webRestApi(RelativePathProvider relativePathProvider) {
		return new Docket(DocumentationType.SWAGGER_2)
				.groupName("1." + componentId + "_web")
				.apiInfo(apiInfo())
				.directModelSubstitute(LocalDateTime.class, Date.class)
				.directModelSubstitute(LocalDate.class, String.class)
				.directModelSubstitute(LocalTime.class, String.class)
				.select()
				.apis(RequestHandlerSelectors.basePackage("com.hikvision"))
				.paths(PathSelectors.regex("^((?!/api/).)*$"))
				.build()
				.pathProvider(relativePathProvider)
				.globalResponseMessage(RequestMethod.GET, getResponseMessageList())
				.globalResponseMessage(RequestMethod.POST, getResponseMessageList());
	}

	/**
	 * 组件api接口swagger
	 */
	@Bean
	public Docket openRestApi(RelativePathProvider relativePathProvider) {
		ParameterBuilder tokenPar = new ParameterBuilder();
		List<Parameter> pars = new ArrayList<>();
		tokenPar.name("Token").description("令牌").modelRef(new ModelRef("string")).parameterType("header").scalarExample("123123").required(true).allowableValues(new AllowableRangeValues("1", "128")).build();
		pars.add(tokenPar.build());
		return new Docket(DocumentationType.SWAGGER_2)
				.groupName("2." + componentId + "_api")
				.host("localhost")
				.apiInfo(apiInfo())
				.directModelSubstitute(LocalDateTime.class, Date.class)
				.directModelSubstitute(LocalDate.class, String.class)
				.directModelSubstitute(LocalTime.class, String.class)
				.produces(Sets.newHashSet("application/json"))
				.consumes(Sets.newHashSet("application/json"))
				.protocols(Sets.newHashSet("http", "https"))
				.select()
				.apis(RequestHandlerSelectors.basePackage("com.hikvision.ccms.api"))
				.paths(Predicates.and(ant("/api/**")))
				.build().globalOperationParameters(pars)
				.pathProvider(relativePathProvider)
				.globalResponseMessage(RequestMethod.GET, getResponseMessageList())
				.globalResponseMessage(RequestMethod.POST, getResponseMessageList());
	}

	/**
	 * RelativePathProvider用于设置basePath
	 */
	@Bean
	public RelativePathProvider relativePathProvider(ServletContext servletContext){
		return new RelativePathProvider(servletContext) {
			@Override
			public String getApplicationBasePath() {
				return "/" + componentId;
			}
		};
	}

	/**
	 * API描述
	 */
	private ApiInfo apiInfo() {
		return new ApiInfoBuilder().title(componentName + "组件" + segmentId + "服务接口").description(componentName + "API接口描述").version(componentVersion).termsOfServiceUrl("http://www.hik-cloud.com/").contact(new Contact(componentSEName, "http://www.hikvision.com/", componentSEName + "@hikvision.com.cn")).build();
	}

	/**
	 * 获取List<ResponseMessage>
	 */
	private List<ResponseMessage> getResponseMessageList() {
		List<ResponseMessage> responseMessageList = new ArrayList<>();
		responseMessageList.add(new ResponseMessageBuilder().code(401).message("Unauthorized").build());
		responseMessageList.add(new ResponseMessageBuilder().code(403).message("Forbidden").build());
		responseMessageList.add(new ResponseMessageBuilder().code(404).message("Not Found").build());
		responseMessageList.add(new ResponseMessageBuilder().code(500).message("Server Error").build());
		return responseMessageList;
	}

	@Override
	public void addResourceHandlers(ResourceHandlerRegistry registry) {
		registry.addResourceHandler("swagger-ui.html").addResourceLocations("classpath:/META-INF/resources/");
		registry.addResourceHandler("/webjars/**").addResourceLocations("classpath:/META-INF/resources/webjars/");
	}

}

```
对应的application.properties配置
```properties
#组件名称 需对应HiCoo上的组件名称
component.name=\u5de5\u5730\u8003\u52e4\u5e94\u7528\u670d\u52a1
#组件id
component.id=ccms
#组件段标识
component.segment.id=ccmsweb
#组件版本
component.version=1.1.100
#组件负责人
component.se.name=yejianhui
#是否启用swagger配置
seashell.swagger.enable=true
```
说明：

1. 由于当前OpenAPI合规性只对组件对外接口有要求，所以配置Swagger时，配置了两个Docket以区分对外接口和前后端分离接口。每个Docket可以通过包名以及URLPath来区分。
2. application.properties上的component.name需要unicode编码
3. 以上配置确保application.properties和cas-client.properties中的不要重复配置

### 补充代码注解

1. Controller增加@API注解

   ![controller api注解](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\controller api注解.bmp)
   注意：  1. tags内容最好以数组加下划线开头便于排序

   ​			 2. 注解字段tags以及description不可缺少

2. Method增加@ApiOperation @ApiImplicitParams @ApiImplicitParam注解：

   ![method注解](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\method注解.bmp)

   注意： 1. 对于Response如果存在泛型**必须设置泛型**否则最后的文档不显示泛型内容，例如上图BaseResponse<List<UnitAttendanceOnlineStatisticsVo>>

   ​			2. 需要填写的注解字段如图，**不能缺少**，特别是example和allowableValues。allowableValues可填写内容可以参照swagger对于该字段的注释，不过**不要使用infinity**，hido校验的时候不认识![allowableValues注释](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\allowableValues注释.bmp)

3. 对于入参对象以及返参对象增加@ApiModel @ApiModelProperty注解：

   ![model注解](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\model注解.bmp)

   注意： 需要填写的注解字段如图，**不能缺少**

### 准备api文档

总共需要6份文档，编写完成后存放于组件代码目录下并推送到SVN。例如：

![api-doc](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\api-doc.bmp)

1. ccms.json：组件openapi json描述文件，**必须以组件标识命名**，例如ccms.json envms.json ihms.json
2. appendix.md：组件数据字典 错误码
3. guidance.md：编程引导
4. statement.md：组件简介
5. tail.md
6. 以上md文件如果涉及到图片，需要文件夹存放相应的图片，该文件夹以及图片名称采用**英文命名，不要出现中文**，最好附带组件标识例如ccms_image_xxxxxx.jpg，否则一旦出现和其他组件图片名称路径一致，容易错误引用到其他组件的图片

#### ccms.json

组件openapi json描述文件通过swagger接口导出，存在2种方法：

1. 通过swagger ui html页面导出，选择对应的group，点击连接，将返回的json复制到文件即可

   ![swagger output json](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\swagger output json.bmp)

   ![json html](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\json html.bmp)

   2. 通过工程Test导出

      1. pom增加plugin配置

         ```xml
         <plugin>
                   <groupId>org.apache.maven.plugins</groupId>
                   <artifactId>maven-surefire-plugin</artifactId>
                   <configuration>
                       <skipTests>true</skipTests>
                       <systemPropertyVariables>
                           <io.springfox.staticdocs.outputDir>${project.build.directory}/swagger</io.springfox.staticdocs.outputDir>
                       </systemPropertyVariables>
                   </configuration>
               </plugin>
         ```

      2. 编写Test

         ```java
         package com.hikvision.ccms.start;
         
         
         import com.hikvision.ccms.common.i18n.I18nUtil;
         import com.hikvision.ccms.common.util.ResponseUtil;
         import com.hikvision.seashell.log.util.LogFormatter;
         import com.hikvision.seashell.util.errorcode.IErrorCode;
         import lombok.extern.slf4j.Slf4j;
         import org.junit.Before;
         import org.junit.Test;
         import org.junit.runner.RunWith;
         import org.reflections.Reflections;
         import org.springframework.beans.factory.annotation.Autowired;
         import org.springframework.boot.test.context.SpringBootTest;
         import org.springframework.http.MediaType;
         import org.springframework.mock.web.MockHttpServletResponse;
         import org.springframework.test.context.junit4.SpringJUnit4ClassRunner;
         import org.springframework.test.web.servlet.MockMvc;
         import org.springframework.test.web.servlet.MvcResult;
         import org.springframework.web.context.WebApplicationContext;
         import springfox.documentation.spring.web.plugins.Docket;
         
         import java.io.BufferedWriter;
         import java.nio.charset.StandardCharsets;
         import java.nio.file.Files;
         import java.nio.file.Paths;
         import java.util.ArrayList;
         import java.util.Arrays;
         import java.util.List;
         import java.util.Locale;
         import java.util.Set;
         
         import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
         import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
         import static org.springframework.test.web.servlet.setup.MockMvcBuilders.webAppContextSetup;
         
         /**
          * SwaggerTest用于导出Swagger Json
          * @author chenyun17
          */
         @RunWith(SpringJUnit4ClassRunner.class)
         @SpringBootTest(classes = WebApplication.class)
         @Slf4j
         public class SwaggerTest {
             private static final String OUTPUT_PATH_PROPERTY_KEY = "io.springfox.staticdocs.outputDir";
             private static final String SWAGGER_API_DOCS_BASE_URL = "/v2/api-docs?group=%s";
             private static final String SWAGGER_JSON_FILE_NAME = "Swagger-%s.json";
         
             @Autowired
             private WebApplicationContext wac;
         
             @Autowired(required = false)
             private List<Docket> dockets;
         
             private MockMvc mockMvc;
         
             @Before
             public void setup() {
                 this.mockMvc = webAppContextSetup(this.wac).build();
             }
         
             /**
              * 导出错误码
              */
             @Test
             public void exportErrorCodeMd() throws Exception {
                 List<IErrorCode> errorCodeList = new ArrayList<>();
                 Reflections reflection = new Reflections("com.hikvision.ccms");
                 Set<Class<? extends IErrorCode>> classSet =  reflection.getSubTypesOf(IErrorCode.class);
                 for(Class<? extends IErrorCode> errorCodeClass : classSet){
                     IErrorCode[] errorCodes = errorCodeClass.getEnumConstants();
                     errorCodeList.addAll(Arrays.asList(errorCodes));
                 }
                 System.out.println(errorCodeList.size());
                 StringBuilder errorCodeMdString = new StringBuilder();
                 errorCodeMdString.append("> **公共错误码**\n");
                 errorCodeMdString.append("\n");
                 errorCodeMdString.append("| 错误码 | 错误提示消息 |\n");
                 errorCodeMdString.append("| ---------- | ------------------- |\n");
                 for (IErrorCode errorCode : errorCodeList) {
                     String code = errorCode.getCode();
                     code = ResponseUtil.formatErrorCode(code);
                     String message = errorCode.getMessage();
                     message = ResponseUtil.i18Format(code, message, null);
                     errorCodeMdString.append("| "+ code + " | " + message + " |\n");
                 }
                 String outputDir = System.getProperty(OUTPUT_PATH_PROPERTY_KEY);
                 Files.createDirectories(Paths.get(outputDir));
                 try (BufferedWriter writer = Files.newBufferedWriter(Paths.get(outputDir, "appendix.md"), StandardCharsets.UTF_8)) {
                     writer.write(errorCodeMdString.toString());
                 }
             }
         
             /**
              * 导出Swagger Json文件
              */
             @Test
             public void exportSwaggerJson() throws Exception {
                 if (dockets == null) {
                     log.info(LogFormatter.toMsg("dockets is not configured, can not export swagger json"));
                     return;
                 }
                 //获取json文件输出路径
                 String outputDir = System.getProperty(OUTPUT_PATH_PROPERTY_KEY);
                 log.info(LogFormatter.toMsg("start export swagger json"));
                 for (Docket docket : dockets) {
                     String groupName = docket.getGroupName();
                     //调用swagger服务获取json数据
                     MvcResult mvcResult = mockMvc.perform(get(String.format(SWAGGER_API_DOCS_BASE_URL, groupName)).accept(MediaType.APPLICATION_JSON)).andExpect(status().isOk()).andReturn();
                     MockHttpServletResponse response = mvcResult.getResponse();
                     String swaggerJson = response.getContentAsString();
                     //写入json数据到文件
                     Files.createDirectories(Paths.get(outputDir));
                     try (BufferedWriter writer = Files.newBufferedWriter(Paths.get(outputDir, String.format(SWAGGER_JSON_FILE_NAME, groupName)), StandardCharsets.UTF_8)) {
                         writer.write(swaggerJson);
                     }
                 }
                 log.info(LogFormatter.toMsg("export swagger json finish, output path is {}", outputDir));
             }
         
         }
         ```

         执行exportSwaggerJson即可导出json文件，执行exportErrorCodeMd即可导出错误码MD文件，导出文件位于io.springfox.staticdocs.outputDir所配置的路径

### 修改hido组件持续集成工作流配置

修改hido组件持续集成工作流配置中的构建命令，在构建过程中将代码路径中的文档复制到组件包dev/api路径下

以ccms组件为例在

```bash
cp -rf ../ccms-package/ccms/*   ../output
```

上增加构建命令：

```bash
rm -rf ../ccms_package/ccms/dev/api/*
cp -rf api-doc/* ../ccms-package/ccms/dev/api/
mv ccms-start/target/swagger/Swagger-2.ccms_api.json ccms-start/target/swagger/ccms.json
cp -rf ccms-start/target/swagger/ccms.json ../ccms_package/ccms/dev/api/
```

如图：

![hido cmd](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\hido cmd.bmp)

### API Display网站审核

经过以上步骤，在组件打包完成后，需要在 http://api-display.hikvision.com.cn/api 网站上进行审核，才能进行显示，默认组件负责人拥有审核权限，如果没有联系李超39处理权限问题

审核位置：

![api display checkout](C:\Users\chenyun17\Desktop\源码笔记\OpenAPI合规性处理Image\api display checkout.bmp)

审核完成之后可以在接口展示栏目查看到对应组件的api文档
