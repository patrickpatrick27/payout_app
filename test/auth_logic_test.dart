import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_app/services/data_manager.dart';

// This generates a Mock class for GoogleSignIn
@GenerateMocks([GoogleSignIn, GoogleSignInAccount])
import 'auth_logic_test.mocks.dart'; 

void main() {
  late DataManager manager;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockGoogleSignInAccount mockUser;

  setUp(() async {
    // 1. Setup Mock Database
    SharedPreferences.setMockInitialValues({});
    
    // 2. Setup Mock Google
    mockGoogleSignIn = MockGoogleSignIn();
    mockUser = MockGoogleSignInAccount();

    // 3. Inject Mock into Manager
    manager = DataManager(googleSignIn: mockGoogleSignIn);
  });

  test('Login Success updates state correctly', () async {
    // ARRANGEMENT: "Train" the mock to return success
    when(mockGoogleSignIn.signIn()).thenAnswer((_) async => mockUser);
    when(mockUser.email).thenReturn("test@example.com");
    when(mockUser.photoUrl).thenReturn("http://fake.photo");
    // Mock headers for Drive API checks (return empty map to avoid crash)
    when(mockUser.authHeaders).thenAnswer((_) async => {});

    // ACTION: Call your app's login
    await manager.login();

    // ASSERTION: Did the app update?
    expect(manager.isAuthenticated, true);
    expect(manager.userEmail, "test@example.com");
    expect(manager.isGuest, false);
  });

  test('Login Failure (User cancels) handles gracefully', () async {
    // ARRANGEMENT: Google returns null (User pressed cancel)
    when(mockGoogleSignIn.signIn()).thenAnswer((_) async => null);

    // ACTION
    await manager.login();

    // ASSERTION: Should still be logged out
    expect(manager.isAuthenticated, false);
    expect(manager.userEmail, null);
  });

  test('Logout clears user data', () async {
    // ARRANGEMENT: Logged in state
    when(mockGoogleSignIn.disconnect()).thenAnswer((_) async => null);
    
    // ACTION
    await manager.logout();

    // ASSERTION
    expect(manager.isAuthenticated, false);
    expect(manager.userEmail, null);
  });
}