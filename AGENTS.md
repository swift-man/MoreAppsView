# MoreAppsView 작업 지침

이 문서는 저장소 전체에 적용된다. 구현 전에 `Package.swift`, `README.md`, 관련 소스와
테스트를 읽고, 현재 공개 API와 플랫폼 동작을 보존한다.

## 프로젝트 경계

- 패키지/라이브러리 product 이름은 `MoreAppsKit`, 핵심 UI는 `MoreAppsView`로 유지한다.
- Swift 5.9 이상, iOS 26.0 이상과 tvOS 26.0 이상만 지원한다. macOS, watchOS,
  visionOS 지원을 암시적으로 추가하지 않는다.
- UI는 UIKit `UICollectionView`와 `UICollectionViewDiffableDataSource`를 사용하고
  ViewController 또는 호스트 앱 전역 상태에 의존하지 않는다.
- 상태 변경과 비동기 효과는 The Composable Architecture reducer를 단일 진입점으로
  삼는다. 교체 가능한 시스템 의존성은 `swift-dependencies`로 주입한다.
- 원격 JSON과 이미지 HTTP 전송에는 Alamofire를 사용한다. 네비게이션, 분석,
  이미지 UI 처리까지 Alamofire 경계를 확장하지 않는다.
- 비공개 API, 특정 앱 목록, 고정 App Store URL, 분석 SDK, 호스트 `Info.plist`
  변경 요구를 패키지에 포함하지 않는다.
- 공개 API는 용도가 분명한 최소 표면만 유지하고 모든 public 선언에 DocC
  문서 주석을 작성한다.

## SOLID 설계 원칙

### 단일 책임 원칙(SRP)

- Model은 데이터 표현, Provider는 카탈로그 수집, Filter는 플랫폼/호스트 규칙,
  Opener는 URL 열기, Reducer는 상태와 효과, View/Cell은 렌더링만 담당한다.
- 이미지 로더는 HTTP 수집·MIME 검증·캐시를 담당하고 셀은 요청 수명과
  재사용 시 UI 정리만 담당한다.

### 개방-폐쇄 원칙(OCP)

- 새 데이터 소스와 URL 열기 정책은 `MoreAppsProviding`, `MoreAppsOpening` 구현을
  추가해 확장하고 기존 UI/리듀서를 수정하지 않는다.
- 시각 정책은 `MoreAppsConfiguration`으로 주입하며 특정 호스트 앱 분기를
  라이브러리에 추가하지 않는다.

### 리스코프 치환 원칙(LSP)

- 모든 Provider는 성공 시 순수한 `[MoreApp]`을 반환하고, 실패 시 비동기 throw로
  일관되게 표현한다. 대체 Provider가 필터링/UI side effect를 숨기지 않는다.
- 모든 Opener는 실제 URL 열기 결과를 `Bool`로 반환하며 deep link fallback 정책은
  Opener 구현이 아닌 reducer에 둔다.

### 인터페이스 분리 원칙(ISP)

- 클라이언트가 필요 없는 네트워크/상태 상세를 알지 않도록 Provider와 Opener
  프로토콜을 각각 하나의 비동기 메서드로 유지한다.
- 분석 연동은 `onEvent` closure로만 노출하고 분석 SDK 프로토콜을 추가하지
  않는다.

### 의존성 역전 원칙(DIP)

- Reducer는 `DependencyValues`의 현재 플랫폼/번들 ID와 URL opener client에만
  의존하고 `Bundle.main`, `UIApplication.shared`를 직접 참조하지 않는다.
- 테스트는 live 네트워크/앱 열기를 사용하지 않고 TCA `TestStore` 또는 프로토콜
  test double로 대체한다.

## 파일 구조와 코드리뷰

- 코드리뷰는 파일 단위로 진행하므로 한 파일에 여러 독립 책임을 누적하지 않는다.
  파일 전체의 상태 흐름과 수명주기를 한 번에 검토하기 어려울 정도로 길어지면
  기능과 책임을 기준으로 타입, extension, 지원 객체를 별도 파일로 분리한다.
- Swift 파일이 500줄을 넘기기 시작하면 분리 가능성을 반드시 검토한다. 800줄
  이상인 파일은 생성 코드나 분리할 수 없는 선언형 데이터처럼 명확한 근거가
  없는 한 구현을 계속 추가하기 전에 먼저 분리한다.
- 큰 타입은 public API와 핵심 상태 전이를 주 파일에 유지하고, 프로토콜 준수,
  UIKit delegate/data source, 렌더링, 네트워크·캐시 지원 로직은 역할별 extension이나
  전용 타입 파일로 나눈다. 분리 과정에서 접근 제어를 불필요하게 넓히지 않는다.
- 테스트도 하나의 거대한 suite에 누적하지 않는다. 대상 타입과 기능 영역을 따라
  파일을 나누고, 정상 경로·실패 경로·동시성 회귀처럼 독립적으로 이해할 수 있는
  시나리오 그룹을 가까이 배치한다.
- 줄 수만 맞추기 위한 기계적 분할이나 서로 강하게 결합된 로직의 무분별한 분산은
  피한다. 파일 분리는 단일 책임, 탐색성, diff 가독성과 리뷰 정확도를 개선해야 한다.

## 상태와 동시성

- 모든 UI 타입과 UI 변경 API는 `@MainActor`에 격리한다.
- Model, Event, Provider 경계는 가능한 `Sendable`로 선언하고 unchecked conformance는
  외부 라이브러리 참조와 같이 피할 수 없는 경계에만 근거를 두고 사용한다.
- 로드 재시작 시 이전 TCA effect를 취소하고 느린 응답이 최신 목록을
  덮어쓰지 않게 한다.
- 셀은 `prepareForReuse` 시 이미지 Task를 취소하고 URL/ID를 재확인한 후만
  이미지를 반영한다.
- 이미지 로더는 동일 URL의 in-flight 요청을 공유하고 메모리 캐시를 사용하며,
  이미지 디코딩으로 메인 스레드를 블로킹하지 않는다.
- closure capture는 순환 참조를 검토하고 UI/Task/delegate의 장기 수명 capture에
  `weak`를 우선한다.

## UI 및 접근성

- Dynamic Type, Dark Mode, VoiceOver를 기본 동작으로 보장한다. 텍스트는 시스템
  text style과 최대 줄 수를 사용하고 색상은 semantic color를 사용한다.
- 카드 전체를 하나의 선택 가능한 접근성 요소로 노출하고 앱 이름, 부제,
  선택 동작을 label/hint/trait에 포함한다.
- tvOS에서 Focus Engine을 막지 않고, 포커스 확대 시 셀이 잘리지 않도록 inset,
  clipping, z-position을 함께 검토한다.
- Reduce Motion이 활성화되면 tvOS 확대량과 애니메이션을 줄인다.
- 플랫폼 필터, 현재 번들 ID 제외, ID 중복 제거, `sortOrder` 정렬은 UI가
  아닌 순수 로직으로 검증한다.

## 검증과 배포

- 모델/필터/Provider/deep link fallback/reducer 이벤트를 Swift Testing의 `@Test`와
  `#expect`로 검증한다. 새 XCTestCase를 추가하지 않는다.
- iOS와 tvOS 각각에 대해 `xcodebuild`로 라이브러리 빌드를 확인하고, 가능한
  시뮬레이터 destination에서 테스트를 실행한다.
- 작업 완료 전에 `README.md`, 샘플 JSON, iOS/tvOS 사용 예제와 public API 문서가
  실제 구현과 일치하는지 확인한다.
- PR 제목에 `Codex`/`codex`를 쓰지 않고 `feat:`, `fix:`, `docs:` 등 변경 유형에
  맞는 접두사를 사용한다. Draft PR은 만들지 않는다.
- PR을 merge한 작업은 원격/로컬 작업 브랜치를 삭제해 정리한다.
