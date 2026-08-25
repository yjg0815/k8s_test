# 주문 연계 시스템

Spring Boot 기반 EAI 연계 시스템입니다. Sender / Mapper / Receiver 구조로 설계하여 주문 실시간 처리(시나리오1)와 운송사 배치 적재(시나리오2)를 구현했습니다.

---

## 시스템 아키텍처

```
[주문자]
    │ XML 요청
    ▼
[Sender] OrderController
    │
    ▼
[Mapper] XML 파싱 → 유효성 검증 → 데이터 변환
    │                        │
    ▼                        ▼
[Receiver-DB]          [Receiver-FTP]
ORDER_TB 적재          영수증 파일 생성 및 FTP 전송

↑ @Transactional — DB + FTP 동기화 (둘 다 성공 시 응답 반환)

---

[Scheduler] 5분 fixedDelay
    │ STATUS=N 조회
    ▼
ORDER_TB → SHIPMENT_TB 적재 → ORDER_TB STATUS=Y 업데이트
```

---

## 기술 스택

| 항목 | 내용 |
|---|---|
| Language | Java 17 |
| Framework | Spring Boot 4.1.0 |
| ORM | Spring Data JPA (Hibernate 7.4) |
| DB | Oracle 19c |
| 파일 전송 | Apache Commons Net (FTP) |
| XML 파싱 | Java StAX (XMLStreamReader) |
| 암복호화 | AES-128 ECB PKCS5Padding |
| 빌드 | Gradle |
| API 문서 | springdoc-openapi (Swagger UI) |

---

## 패키지 구조

```
com.assignment.inspien
├── sender          # Sender — 외부 요청 수신 (OrderController)
├── mapper          # Mapper — XML 파싱, 데이터 변환 (OrderXmlParser, OrderConverter 등)
├── receiver        # Receiver — DB 적재, FTP 전송 (OrderDbReceiver, ReceiptFtpService)
├── service         # 흐름 조율 (OrderService, ShipmentService)
├── scheduler       # 5분 배치 (ShipmentScheduler)
├── domain          # Entity (Order, Shipment)
├── repository      # JPA Repository
├── dto             # 요청/응답 DTO
├── validator       # 유효성 검증 (OrderValidator)
├── apiPayload      # 공통 응답, 에러 코드, 예외 처리
└── config          # 복호화 유틸 (AesDecryptUtil)
```

---

## 시나리오1 — 주문 실시간 처리

### API

```
POST /api/orders
Content-Type: application/xml
```

### 요청 형식

루트 태그 없이 `<HEADER>` / `<ITEM>` 나열 구조 (HEADER:ITEM = 1:N)

```xml
<HEADER>
    <USER_ID>USER01</USER_ID>
    <NAME>홍길동</NAME>
    <ADDRESS>서울특별시 강남구</ADDRESS>
    <STATUS>N</STATUS>
</HEADER>
<ITEM>
    <USER_ID>USER01</USER_ID>
    <ITEM_ID>ITEM01</ITEM_ID>
    <ITEM_NAME>청바지</ITEM_NAME>
    <PRICE>21000</PRICE>
</ITEM>
```

### 처리 흐름

1. XML 파싱 (StAX 기반, 비표준 멀티루트 구조 처리)
2. 유효성 검증 (HEADER/ITEM 누락 여부)
3. ORDER_TB 적재 (ORDER_ID: 알파벳 대문자 1개 + 숫자 3개)
4. 영수증 파일 생성 → FTP 전송 (EUC-KR 인코딩, 3회 재시도)
5. DB + FTP 동기화 (`@Transactional`) — 둘 다 성공 시 JSON 응답 반환

### 응답

```json
{
  "isSuccess": true,
  "code": "ORDER2001",
  "message": "주문 생성 및 연계 처리 성공"
}
```

---

## 시나리오2 — 운송사 배치

- 5분 주기 (`fixedDelay`, `application.yaml`에서 관리)
- `ORDER_TB`에서 `APPLICANT_KEY` + `STATUS=N` 기준 미전송 주문 조회
- `SHIPMENT_TB` 적재 (SHIPMENT_ID: 알파벳 대문자 1개 + 숫자 3개)
- 적재 성공 건 `ORDER_TB.STATUS` → `Y` 업데이트

---

## 예외 처리

| 에러 코드 | 상황 |
|---|---|
| ORDER4001 | 요청 XML 형식 오류 또는 HEADER/ITEM 누락 |
| ORDER5001 | DB 적재 실패 |
| ORDER5002 | FTP 전송 실패 (3회 재시도 후 최종 실패) |
| COMMON5001 | 서버 내부 오류 |

---

## 운영 로그

실행 중 발생하는 모든 요청/응답/에러 로그는 로컬 파일에 저장됩니다.

```
./logs/eai-log.txt
```

---

## 로컬 실행 방법

### 1. 사전 준비

`src/main/resources/application-secret.yaml` 파일을 직접 생성하고 아래 항목을 채웁니다.
(`application-secret.yaml.example` 참고)

```yaml
EAI_DB_URL: jdbc:oracle:thin:@{HOST}:{PORT}:{SID}
EAI_DB_USERNAME: "{USERNAME}"
EAI_DB_PASSWORD: "{PASSWORD}"

EAI_FTP_HOST: "{FTP_HOST}"
EAI_FTP_PORT: "{FTP_PORT}"
EAI_FTP_USERNAME: "{FTP_USERNAME}"
EAI_FTP_PASSWORD: "{FTP_PASSWORD}"
EAI_FTP_PATH: "{FTP_PATH}"

EAI_APPLICANT_KEY: "{APPLICANT_KEY}"
EAI_APPLICANT_NAME: "{이름}"
EAI_APPLICANT_PHONE: "{전화번호}"
EAI_APPLICANT_EMAIL: "{이메일}"

EAI_API_URL: "{API_URL}"
EAI_API_AUTH_USERNAME: "{AUTH_USERNAME}"
EAI_API_AUTH_PASSWORD: "{AUTH_PASSWORD}"
```

### 2. 빌드 및 실행

```bash
./gradlew build
./gradlew bootRun
```

### 3. API 문서

```
http://localhost:8080/swagger-ui.html
```

---

## 브랜치 전략

| 브랜치 | 내용 |
|---|---|
| `feat/decrypt` | AES-128 복호화, 접속 정보 API 연동 |
| `feat/domain` | Order / Shipment Entity, Repository |
| `feat/order-api` | 시나리오1 전체 (Sender/Mapper/Receiver, FTP) |
| `feat/batch` | 시나리오2 배치, FTP 재시도 로직, 운영 로그 |
