import '../../domain/finanzas/financial_category.dart';
import '../../domain/finanzas/financial_direction.dart';
import '../../domain/finanzas/financial_nature.dart';
import '../../domain/repositories/financial_category_repository.dart';
import '../local/drift/app_database.dart';

class FinancialCategoryRepositoryImpl implements FinancialCategoryRepository {
  FinancialCategoryRepositoryImpl(this._dao);
  final FinancialCategoryDao _dao;

  @override
  Stream<List<FinancialCategory>> watchCategories() => _dao
      .watchCategories()
      .map(
        (rows) => rows
            .map(
              (row) => FinancialCategory(
                id: row.id,
                name: row.name,
                direction: FinancialDirection.fromCode(row.direction),
                nature: FinancialNature.fromCode(row.nature),
              ),
            )
            .toList(),
      );
}