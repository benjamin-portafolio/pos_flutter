import '../creditos/customer_account.dart';

abstract interface class CustomerAccountRepository {
  Stream<CustomerAccount> watchAccount(String clienteId);
}
