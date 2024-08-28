+----------------------------+
WHERE TO PUT THINGS?
+----------------------------+

api
================================

All remote interfaces and POJOs used by other services. This is the place where to declare dependency on all APIs available in SDK.
This is the module other services will depend on (compile time) when using your service.
Anything found in this module will be considered part of your interface and you will have to maintain backward compatibility.

All SDK API dependencies in this module must be marked as "provided" scope.
This module must not depend on any SDK implementations.




jar
================================

CDI (non-JEE) implementation. Might be used when testing JSE environment. Should not use anything not available in CDI environment
(JEE things, for example).

All SDK API dependencies in this module must be marked as "provided" scope.
This module must not depend on any SDK implementations.




ejb
================================

JEE wrapper around (mostly for remoting and transaction management) around jar module.
Should contain only EJBs (SLSB, SFSB, Singletons).

All SDK API dependencies in this module must be marked as "provided" scope.
This module must not depend on any SDK implementations.




war
================================

All web implementation artifacts: Restful services, Servlets, JSPs etc

All SDK API dependencies in this module must be marked as "provided" scope.
This module must not depend on any SDK implementations.




ear
================================

Responsible for packaging whole project.
The final package (EAR) must not contain any Service Framework jar (sdk-xxx.jar or sdk-xxx-api.jar)
either in itself or its sub-modules (WAR).
The Service Framework Distribution jar has been removed from ServiceFramework version 4.6.2.
Service Framework 4.x is now added as a global module to the standalone-eap7-enm.xml.
The final package (EAR) must not contain any plexus*, solder*, slf4j*, infinispan-cdi*, juel*, openaz*, jgroups*, cache-api*, commons* or 
maven-plugin* jar file either in itself or its sub-modules (WAR).

This module must not depend on any SDK API or SDK implementations.




testsuite
================================

See README.TXT under testsuite folder for more details.




+----------------------------+
BUILDING
+----------------------------+

- Do "mvn clean install" under the root project folder for basic building and firing unit tests. 


+----------------------------+
TESTING
+----------------------------+

- Check README.TXT under testsuite module for details of testing.


+----------------------------+
DEPLOYING TO JBOSS
+----------------------------+

- System property JBOSS_HOME should point to the installation folder of JBoss (EAP7 - not community version).
- Once you started JBoss you have to execute mvn jboss-as:deploy to deploy service

