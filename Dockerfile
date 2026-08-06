# 대문자 키워드 -> Docker 전용 지시어 문법 

FROM eclipse-temurin:17-jdk AS build 
# Temurin 프로젝트가 배포하는 Java 17 JDK 이미지 -> 이걸 베이스로 깔고 파일을 더 얹어서 새 이미지 생성 

WORKDIR /app

COPY gradlew .
COPY gradle gradle
COPY build.gradle settings.gradle ./
# src 전에 빌드 설정파일 복사 

RUN chmod +x gradlew
# 실행권한 부여 

RUN ./gradlew --no-daemon dependencies || true
# docker는 layer 단위로 캐시(FROM, COPY, RUN 등 실행할 때마다 스냅샷 -> 재빌드할 때 이전과 상태가 같으면 실행 x 재사용) 
# src를 먼저 실행하면 src가 바뀔 때마다 gradle이 다시 실행되므로, src를 복사하기 전에 dependencies를 먼저 실행하여 캐시 활용
# daemon -> 사용자가 직접 호출하지 않아도 백그라운드에서 계속 떠 있으면서 요청을 처리하는 프로세스
# 같은 프로젝트를 반복 빌드할 때(주로 로컬 상황) JVM 프로세스를 매번 새로 켜지 않고 백그라운드에 daemon을 살려두고 재사용 -> 빌드 속도 향상 
# 근데 docker는 매번 새로 빌드하므로 daemon을 켜두는게 의미가 없음 -> --no-daemon 옵션으로 끄고 실행
# || true : gradle이 실패해도 무시하고 다음 단계 진행

COPY src src
RUN ./gradlew --no-daemon bootJar -x test
# 실행 가능한 jar 빌드 (테스트 제외 -> 빌드시간 단축)

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
# jar 파일만 복사 (gradle 빌드 산출물)

EXPOSE 8080
# 해당 컨테이너가 사용하는 포트 번호를 명시 (외부에서 접근 가능하도록) -> 실제 포트 개방은  compose의 ports 가 진행 
ENTRYPOINT ["java", "-jar", "app.jar"]
# 컨테이너가 시작될 때 실행하는 명령 

# docker build를 하면 Docker가 Dockerfile을 읽고 FROM부터 순서대로 실행 -> build 단계에서 gradle 빌드 후 jar 생성 -> run 단계에서 jar 실행
