// 后端项目的“构建与部署”有没有哪一种正在跑（打包页用它锁住三选一和“项目类型”）。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/deploy_github.dart';
import 'package:lopicode/state/deploy_local.dart';
import 'package:lopicode/state/deploy_ssh.dart';
import 'package:riverpod/riverpod.dart';

final deployBusyProvider = Provider.family<bool, ProjectSession>(
  (ref, session) =>
      ref.watch(deployLocalProvider(session).select((s) => s.busy)) || ref.watch(deployGithubProvider(session).select((s) => s.busy)) || ref.watch(deploySshProvider(session).select((s) => s.busy)),
);
