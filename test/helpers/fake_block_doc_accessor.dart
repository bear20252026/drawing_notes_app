// 测试假件（审计 2026-09-26 #17）：HomePage 的 blockDocAccessor 改为
// required 注入后，测试构造需要一个访问器——列表/同步/新建失败等用例
// 不触达搜索路径，空实现返回空集即可。
import 'package:drawing_notes_app/core/notes_accessor.dart';

class FakeBlockDocAccessor implements IBlockDocSearchAccessor {
  const FakeBlockDocAccessor();

  @override
  Future<List<BlockDocSearchHit>> search(String query) async => const [];
}
