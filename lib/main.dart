import 'package:flutter/widgets.dart';

import 'app/app_dependencies.dart';
import 'app/prompt_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PromptApp(dependencies: AppDependencies.create()));
}
