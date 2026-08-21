# ADB KakaoLink Intent Capture

루트나 대상 APK 수정 없이 ADB shell에서 explicit KakaoTalk 공유 Intent의 `kakaolink://send/...` data URI를 캡처해 Windows 클립보드로 복사하는 고급 사용자용 도구입니다.

일반 Android intent-filter 앱은 대상 package/component가 명시된 explicit Intent를 받을 수 없습니다. 이 도구는 Android의 hidden `IActivityController` 테스트 인터페이스를 ADB shell UID에서 일시적으로 등록해 Activity가 시작되기 직전의 filter Intent를 관찰합니다.

## 요구 사항

- Windows PowerShell 5.1 또는 PowerShell 7
- JDK 17 이상 (`java`, `javac`, `jar`)
- Android SDK Platform 36 및 Build Tools `36.1.0`
- USB 또는 무선 ADB가 허용된 본인 소유·관리 기기

## 사용법

기본 모드는 원본 data URI를 복사하고 원래 KakaoTalk 공유 화면을 엽니다.

```powershell
.\capture.ps1 -Once
```

GitHub Pages URL로 만들어 복사하려면 표준 PowerShell switch `-Link`를 명시합니다.

```powershell
.\capture.ps1 -Once -Link
```

원래 공유 화면을 열지 않으려면 `-BlockLaunch`를 조합합니다.

```powershell
.\capture.ps1 -Once -BlockLaunch
.\capture.ps1 -Once -BlockLaunch -Link
```

네 가지 핵심 조합은 다음과 같습니다.

| 명령 | 클립보드 | KakaoTalk 공유 화면 |
| --- | --- | --- |
| `-Once` | 원본 data URI | 허용 |
| `-Once -Link` | Pages URL | 허용 |
| `-Once -BlockLaunch` | 원본 data URI | 차단 |
| `-Once -BlockLaunch -Link` | Pages URL | 차단 |

여러 기기가 연결돼 있으면 승인·확인한 serial을 반드시 지정하세요.

```powershell
.\capture.ps1 -Serial SERIAL -Once
```

## 옵션

- `-Once`: 첫 캡처 후 종료
- `-Link`: `https://portable-uri-workshop.github.io/#to=<encoded URI>` 생성
- `-BlockLaunch`: 정상적으로 queue에 등록된 KakaoTalk 공유 Activity 시작 취소
- `-NoClipboard`: PC 클립보드를 변경하지 않음
- `-ShowRawUri`: 진단 목적으로 제어문자를 제거한 raw URI를 콘솔에 표시
- `-SkipBuild`: 기존 `out/adb-intent-capture.jar` 재사용
- `-Serial SERIAL`: 여러 ADB 기기 중 승인된 하나를 정확히 선택
- `-Verbose`: 전체 serial, 절대 경로, 인자 API 등 진단정보 표시

`--link` 별칭은 지원하지 않습니다.

## BlockLaunch와 안정성

`-BlockLaunch`는 URI scheme `kakaolink`, host `send`, target/component package `com.kakao.talk` 조건이 모두 맞고 capture record가 정상 queue 등록된 Activity만 취소합니다. 나머지 Activity, 64KiB를 초과한 URI, queue full, writer 오류는 모두 fail-open으로 허용합니다.

Binder callback은 stdout을 직접 쓰지 않습니다. 용량 16의 `ArrayBlockingQueue`에 record를 넣고 즉시 반환하며 별도 writer thread가 Base64와 stdout 처리를 담당합니다. 종료 시 controller 해제, queue drain, writer join, PC process 종료, stderr 회수, 원격 JAR 삭제 순서로 정리합니다.

연속 `-BlockLaunch`는 모니터 실행 중 모든 일치 Activity를 차단하므로 보통 `-Once -BlockLaunch`를 권장합니다. 원 앱은 Activity 시작 실패를 오류·로딩·재시도로 표시할 수 있습니다.

## 보안·기기 안전

- raw URI와 Pages URL은 동일하게 민감합니다. 토큰이나 식별값이 포함될 수 있으므로 공개 게시하지 마세요.
- Pages URL은 생성 시 로컬에서 만들어지지만, 실제로 URL을 열면 브라우저와 대상 앱이 이후 처리를 담당합니다. redirector source는 별도 공개 저장소에서 확인할 수 있습니다.
- Windows 클립보드 기록·클라우드 동기화가 활성화돼 있으면 값이 보존·동기화될 수 있습니다.
- ADB 접근은 기기에 광범위한 권한을 제공합니다. 신뢰하는 PC와 본인 소유 기기에서만 사용하세요.
- `capture.ps1`은 실행 즉시 `adb devices -l`을 호출하고 JAR를 push합니다. 여러 작업에서 기기를 번갈아 연결한다면 실행 직전에 대상 serial/model을 직접 확인하세요.
- ActivityController는 시스템 전체에서 하나만 사용할 수 있으므로 다른 `am monitor` 또는 테스트 controller와 동시에 실행하지 마세요.
- 정상 종료 시 controller를 해제하고 `/data/local/tmp/adb-intent-capture.jar`를 삭제합니다. 비정상 상태가 의심되면 ADB 연결을 끊거나 기기를 재부팅하세요.

기본 출력은 기기 serial을 마스킹하고 결과 경로를 project-relative로 표시합니다. 공개할 터미널 캡처에는 `-Verbose` 출력을 포함하지 않는 편이 안전합니다.

## 호환성 경계

`IActivityController`와 `setActivityController`는 일반 앱용 공개 API가 아닌 Android 테스트용 hidden API입니다. Android 버전·OEM 정책에 따라 제한되거나 깨질 수 있으며 휴대폰 단독 앱으로는 동작하지 않습니다.

Android가 controller에 전달하는 Intent는 `cloneFilter()` 결과라 extras가 제거될 수 있습니다. 이 도구는 data URI가 핵심 payload인 KakaoLink 캡처에 맞춰져 있습니다.

## 빌드와 테스트

휴대폰이나 ADB 없이 Java 정책, PowerShell quoting, 5.1/7 parser 호환을 테스트합니다.

```powershell
.\test.ps1
.\build.ps1
```

빌드는 정확히 Platform 36과 Build Tools `36.1.0`을 사용하며 결과는 `out/adb-intent-capture.jar`입니다. 컴파일 전용 hidden API stub은 DEX에 포함되지 않습니다.

공식 v2 Release에는 다음이 포함됩니다.

- prebuilt DEX JAR와 SHA-256
- `capture.ps1`, build/test source, prebuilt JAR를 포함한 Windows bundle ZIP과 SHA-256
- 두 artifact의 GitHub Artifact Attestation

```bash
gh attestation verify adb-kakaolink-capture-v2.0.0.jar \
  -R portable-uri-workshop/adb-kakaolink-capture
gh attestation verify adb-kakaolink-capture-windows-v2.0.0.zip \
  -R portable-uri-workshop/adb-kakaolink-capture
```

## 관련 도구와 차이

- [Intent Intercept](https://f-droid.org/packages/de.k3b.android.intentintercept/)는 chooser에서 수신 가능한 Intent를 확인하지만 다른 package/component로 고정된 explicit Intent는 받을 수 없습니다.
- AOSP의 `adb shell am monitor`는 같은 ActivityController 계열이지만 이 도구처럼 KakaoLink URI를 PC clipboard로 전달하지 않습니다.
- Xposed 기반 분석 도구는 더 넓은 API를 관찰할 수 있지만 root/Xposed와 대상 프로세스 hooking이 필요합니다.

## 라이선스

프로젝트 코드는 [MIT License](LICENSE)입니다. 컴파일 전용 Android hidden API 선언의 AOSP 고지와 [Apache License 2.0](LICENSE-APACHE-2.0)은 [NOTICE](NOTICE)를 확인하세요.
