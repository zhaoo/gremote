// Explicit device-only smoke flow. It never connects, imports a key, or writes
// camera state automatically. The hardware write matrix is in acceptance.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gremote/app/bootstrap.dart';
import 'package:gremote/app/router.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline workbench navigation and honest camera capability state',
      (tester) async {
    await bootstrap();
    appRouter.go('/film-workbench');
    await tester.pumpAndSettle();
    expect(find.text('试卷台'), findsWidgets);
    await tester.tap(find.text('数字胶卷').last);
    await tester.pumpAndSettle();
    expect(find.text('数字胶卷'), findsWidgets);
    await tester.tap(find.text('相机胶卷').last);
    await tester.pumpAndSettle();
    expect(find.text('导入配对文件'), findsOneWidget);
    expect(find.text('导入胶卷数据'), findsWidgets);
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('CAMERA_ACCEPTANCE'));
}
