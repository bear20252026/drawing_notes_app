package gov.drawingnotes.drawing_notes_app

// FlutterFragmentActivity：local_auth 在 Android 端走 BiometricPrompt，
// 要求宿主 Activity 是 FragmentActivity（FlutterActivity 不满足）。
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
