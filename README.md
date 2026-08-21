# ADB KakaoLink Intent Capture

루트나 대상 APK 수정 없이, ADB shell에서 explicit KakaoTalk 공유 Intent의 `kakaolink://send/...` URI를 캡처해 휴대폰 대신 Windows PC 클립보드로 복사하는 고급 사용자용 도구입니다.

일반 Android intent-filter 앱은 대상 package/component가 명시된 explicit Intent를 받을 수 없습니다. 이 도구는 Android의 hidden `IActivityController` 테스트 인터페이스를 ADB shell UID에서 일시적으로 등록해 Activity가 시작되기 직전의 filter Intent를 관찰합니다.

## 요구 사항

- Windows PowerShell 5.1 또는 PowerShell 7
- JDK (`java`, `javac`, `jar`)
- Android SDK Platform 및 Build Tools (`android.jar`, `d8.bat`)
- USB 또는 무선 ADB가 허용된 본인 소유·관리 기기

## 사용법

한 번 캡처하고 원래 KakaoTalk 공유 화면은 그대로 열기:

```powershell
.\capture.ps1 -Once
```

한 번 캡처하고 원래 KakaoTalk 공유 화면은 열지 않기:

```powershell
.\capture.ps1 -Once -BlockLaunch
```

여러 번 계속 캡처:

```powershell
.\capture.ps1
```

기기가 여러 대라면:

```powershell
.\capture.ps1 -Serial SERIAL -Once
```

기본 동작은 raw URI를 파일이나 콘솔에 남기지 않고 다음 redirect URL을 Windows 클립보드에 넣습니다.

```text
https://deep-link-redirector.major-kite-5089.chatgpt.site/#to=<Android Uri.encode 결과>
```

### BlockLaunch 모드

`-BlockLaunch`는 다음 조건이 모두 맞는 Activity 시작만 취소합니다.

- URI scheme: `kakaolink`
- URI host: `send`
- target package 또는 explicit component package: `com.kakao.talk`

나머지 Activity와 캡처 오류 경로는 항상 허용합니다. 연속 모드에서 `-BlockLaunch`를 사용하면 모니터가 실행되는 동안 조건에 맞는 모든 KakaoTalk 공유 Activity를 차단하므로 일반적으로 `-Once -BlockLaunch` 조합을 권장합니다.

차단 모드에서는 원 앱이 해당 Activity 시작 실패를 자체 오류·로딩·재시도로 표시할 수 있습니다.

## 옵션

- `-Once`: 첫 캡처 후 종료
- `-BlockLaunch`: 캡처한 KakaoTalk 공유 Activity 시작 취소
- `-NoClipboard`: PC 클립보드를 변경하지 않음
- `-ShowRawUri`: 진단 목적으로 raw URI를 콘솔에 표시
- `-SkipBuild`: 기존 `out/adb-intent-capture.jar` 재사용
- `-Serial SERIAL`: 여러 ADB 기기 중 하나 선택

## 보안 및 개인정보

- raw URI와 생성된 redirect URL은 동일하게 민감합니다. 서비스 식별값이나 토큰이 포함될 수 있으므로 공개 게시하지 마세요.
- Windows 클립보드 기록 또는 클라우드 클립보드 동기화가 활성화돼 있으면 링크가 보존·동기화될 수 있습니다.
- ADB 접근은 기기에 광범위한 권한을 제공합니다. 신뢰하는 PC에서만 사용하고 작업 후 필요하면 USB 디버깅 승인을 해제하세요.
- 이 도구는 시스템 전체 Activity 시작 콜백을 받지만 `kakaolink://send`와 KakaoTalk target만 캡처합니다.
- ActivityController는 시스템 전체에서 하나만 사용할 수 있으므로 다른 `am monitor` 또는 테스트 controller와 동시에 실행하지 마세요.
- 정상 종료 시 controller를 해제하고 `/data/local/tmp/adb-intent-capture.jar`를 삭제합니다. 비정상 상태가 의심되면 ADB 연결을 끊거나 기기를 재부팅하세요.

## 호환성 경계

`IActivityController`와 `setActivityController`는 일반 앱용 공개 API가 아닌 Android 테스트용 hidden API입니다. 현재 확인된 기기에서는 동작하지만 Android 버전·OEM 정책에 따라 향후 제한되거나 깨질 수 있습니다. 휴대폰 단독 앱으로는 동작하지 않으며 ADB 연결이 유지돼야 합니다.

Android가 controller에 전달하는 Intent는 `cloneFilter()` 결과라 extras가 제거될 수 있습니다. 이 도구는 data URI가 핵심 payload인 KakaoLink 캡처에 맞춰져 있습니다.

## 빌드와 테스트

휴대폰 없이 필터와 allow/block 정책 테스트:

```powershell
.\test.ps1
```

DEX JAR 빌드:

```powershell
.\build.ps1
```

결과는 `out/adb-intent-capture.jar`에 생성됩니다. 컴파일 전용 hidden API stub은 결과 DEX에 포함되지 않으며 런타임에는 Android boot class path의 실제 인터페이스를 사용합니다.

공식 GitHub Release JAR는 Windows PowerShell 5.1에서 테스트·빌드되고 GitHub Artifact Attestation이 생성됩니다.

```bash
gh attestation verify adb-kakaolink-capture-v1.0.0.jar \
  -R portable-uri-workshop/adb-kakaolink-capture
```

## 관련 도구와 차이

- [Intent Intercept](https://f-droid.org/packages/de.k3b.android.intentintercept/)는 Android 앱으로 수신 가능한 Intent를 chooser에서 선택해 내용을 확인하고 다시 보낼 수 있습니다. 다른 package/component로 고정된 explicit Intent는 후보가 될 수 없습니다.
- AOSP의 `adb shell am monitor`는 같은 ActivityController 계열이지만 기본 UI는 주로 crash/ANR 모니터링에 초점이 있고 이 도구처럼 KakaoLink URI를 PC 클립보드로 전달하지 않습니다.
- [Inspeckage](https://github.com/ac-pm/Inspeckage) 같은 Xposed 동적 분석 도구는 더 넓은 API 호출을 관찰할 수 있지만 root/Xposed 환경과 대상 프로세스 hooking이 필요합니다.

이 프로젝트는 루트·APK 패치·대상 앱 hooking 없이 ADB shell에서 explicit KakaoLink Activity 시작을 관찰하고 선택적으로 취소하는 좁은 용도의 도구입니다.

## 라이선스

프로젝트 코드는 [MIT License](LICENSE)입니다. 컴파일 전용 Android hidden API 선언에 관한 고지는 [NOTICE](NOTICE)를 확인하세요.
