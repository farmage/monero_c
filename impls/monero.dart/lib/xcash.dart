library;

// Are we memory safe?
// There is a simple way to check that:
// 1) Rewrite everything in rust
// Or, assuming we are sane
// 1) grep -E 'toNative|^String ' lib/monero.dart | grep -v '^//' | grep -v '^String libPath = ' | wc -l
//    This will print number of all things that produce pointers
// 2) grep .free lib/monero.dart | grep -v '^//' | wc -l
//    This will print number of all free calls, these numbers should match

// Wrapper around generated_bindings.g.dart - to provide easy access to the
// underlying functions, feel free to not use it at all.

//  _____________ PendingTransaction is just a typedef for Pointer<Void> (which is void* on C side)
// /                   _____________ Wallet class, we didn't specify the MONERO prefix because we import the monero.dart code with monero prefix
// |                  /       _____________ createTransaction function, from the upstream in the class Wallet
// |                  |      /
// PendingTransaction Wallet_createTransaction(wallet ptr, <------------- wallet is a typedef for Pointer<Void>
//     {required String dst_addr,--------------------------------\ All of the parameters that are used in this function
//     required String payment_id,                  _____________/ String - will get casted into const char*
//     required int amount,                        /
//     required int mixin_count,                  /                int - goes as it is
//     required int pendingTransactionPriority,  /
//     required int subaddr_account,            /
//     List<String> preferredInputs = const []}) {                 List<String> - gets joined and passed as 2 separate parameters to be split in the C side____
//   debugStart?.call('XCASH_Wallet_createTransaction'); <------------- debugStart functions just marks the function as currently being executed, used        |
//   lib ??= XcashC(DynamicLibrary.open(libPath));                    \_for performance debugging                                                             |
//   \_____________ Load the library in case it is not loaded                                                                                                  |
//   final dst_addr_ = dst_addr.toNativeUtf8().cast<Char>(); -----------------| Cast the strings into Chars so it can be used as a parameter in a function     |
//   final payment_id_ = payment_id.toNativeUtf8().cast<Char>(); -------------| generated via ffigen                                                           |
//   final preferredInputs_ = preferredInputs.join(defaultSeparatorStr).toNativeUtf8().cast<Char>(); <---------------------------------------------------------/
//   final s = lib!.WOWNERO_Wallet_createTransaction(-------------|
//     ptr,                                                       |
//     dst_addr_,                                                 |
//     payment_id_,                                               |
//     amount,                                                    |
//     mixin_count,                                               | Call the native function using generated code
//     pendingTransactionPriority,                                |
//     subaddr_account,                                           |
//     preferredInputs_,                                          |
//     defaultSeparator,                                          |
//   );___________________________________________________________/
//   calloc.free(dst_addr_);---------------| Free the memory once we don't need it
//   calloc.free(payment_id_);-------------|
//   debugEnd?.call('XCASH_Wallet_createTransaction'); <------------- Mark the function as executed
//   return s; <------------- return the value
// }
//
// Extra case is happening when we have a function call that returns const char* as we have to be memory safe
// String PendingTransaction_txid(PendingTransaction ptr, String separator) {
//   debugStart?.call('XCASH_PendingTransaction_txid');
//   lib ??= XcashC(DynamicLibrary.open(libPath));
//   final separator_ = separator.toNativeUtf8().cast<Char>();
//   final txid = lib!.XCASH_PendingTransaction_txid(ptr, separator_);
//   calloc.free(separator_);
//   debugEnd?.call('XCASH_PendingTransaction_txid');
//   try { <------------- We need to try-catch these calls because they may fail in an unlikely case when we get an invalid UTF-8 string,
//     final strPtr = txid.cast<Utf8>();                                            it is better to throw than to crash main isolate imo.
//     final str = strPtr.toDartString(); <------------- convert the pointer to const char* to dart String
//     XCASH_free(strPtr.cast()); <------------- free the memory
//     debugEnd?.call('XCASH_PendingTransaction_txid');
//     return str; <------------- return the value
//   } catch (e) {
//     errorHandler?.call('XCASH_PendingTransaction_txid', e);
//     debugEnd?.call('XCASH_PendingTransaction_txid');
//     return ""; <------------- return an empty string in case of an error.
//   }
// }
//

// ignore_for_file: non_constant_identifier_names, camel_case_types

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:monero/src/generated_bindings_xcash.g.dart';

export 'src/checksum_xcash.dart';

typedef PendingTransaction = Pointer<Void>;

XcashC? lib;
String libPath = (() {
  if (Platform.isWindows) return 'xcash_libwallet2_api_c.dll';
  if (Platform.isMacOS) return 'xcash_libwallet2_api_c.dylib';
  if (Platform.isIOS) return 'XcashWallet.framework/MoneroWallet';
  if (Platform.isAndroid) return 'libxcash_libwallet2_api_c.so';
  return 'xcash_libwallet2_api_c.so';
})();

Map<String, List<int>> debugCallLength = {};

final defaultSeparatorStr = ";";
final defaultSeparator = defaultSeparatorStr.toNativeUtf8().cast<Char>();
/* we don't call .free here, this comment serves one purpose - so the numbers match :) */

final Stopwatch sw = Stopwatch()..start();

bool printStarts = false;

void Function(String call)? debugStart = (call) {
  try {
    if (printStarts) print("XCASH: $call");
    debugCallLength[call] ??= <int>[];
    debugCallLength[call]!.add(sw.elapsedMicroseconds);
  } catch (e) {}
};
void debugChores() {
  for (var key in debugCallLength.keys) {
    if (debugCallLength[key]!.length > 1000000) {
      final elm =
          debugCallLength[key]!.reduce((value, element) => value + element);
      debugCallLength[key]!.clear();
      debugCallLength["${key}_1M"] ??= <int>[];
      debugCallLength["${key}_1M"]!.add(elm);
    }
  }
}

int debugCount = 0;

void Function(String call)? debugEnd = (call) {
  try {
    final id = debugCallLength[call]!.length - 1;
    if (++debugCount > 1000000) {
      debugCount = 0;
      debugChores();
    }
    debugCallLength[call]![id] =
        sw.elapsedMicroseconds - debugCallLength[call]![id];
  } catch (e) {}
};
void Function(String call, dynamic error)? errorHandler = (call, error) {
  print("$call: $error");
};

int PendingTransaction_status(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_status');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_PendingTransaction_status(ptr);
  debugEnd?.call('XCASH_PendingTransaction_status');
  return status;
}

String PendingTransaction_errorString(PendingTransaction ptr) {
  lib ??= XcashC(DynamicLibrary.open(libPath));
  debugStart?.call('XCASH_PendingTransaction_errorString');
  try {
    final rPtr = lib!.XCASH_PendingTransaction_errorString(ptr).cast<Utf8>();
    final str = rPtr.toDartString();
    XCASH_free(rPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_errorString');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_errorString', e);
    debugEnd?.call('XCASH_PendingTransaction_errorString');
    return "";
  }
}

bool PendingTransaction_commit(PendingTransaction ptr,
    {required String filename, required bool overwrite}) {
  debugStart?.call('XCASH_PendingTransaction_commit');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final filename_ = filename.toNativeUtf8().cast<Char>();
  final result =
      lib!.XCASH_PendingTransaction_commit(ptr, filename_, overwrite);
  calloc.free(filename_);
  debugEnd?.call('XCASH_PendingTransaction_commit');
  return result;
}

String PendingTransaction_commitUR(
    PendingTransaction ptr, int max_fragment_length) {
  debugStart?.call('XCASH_PendingTransaction_commitUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid =
      lib!.XCASH_PendingTransaction_commitUR(ptr, max_fragment_length);
  debugEnd?.call('XCASH_PendingTransaction_commitUR');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_commitUR');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_commitUR', e);
    debugEnd?.call('XCASH_PendingTransaction_commitUR');
    return "";
  }
}

int PendingTransaction_amount(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_amount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final amount = lib!.XCASH_PendingTransaction_amount(ptr);
  debugStart?.call('XCASH_PendingTransaction_amount');
  return amount;
}

int PendingTransaction_dust(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_dust');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final dust = lib!.XCASH_PendingTransaction_dust(ptr);
  debugStart?.call('XCASH_PendingTransaction_dust');
  return dust;
}

int PendingTransaction_fee(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_fee');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final fee = lib!.XCASH_PendingTransaction_fee(ptr);
  debugEnd?.call('XCASH_PendingTransaction_fee');
  return fee;
}

String PendingTransaction_txid(PendingTransaction ptr, String separator) {
  debugStart?.call('XCASH_PendingTransaction_txid');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final separator_ = separator.toNativeUtf8().cast<Char>();
  final txid = lib!.XCASH_PendingTransaction_txid(ptr, separator_);
  calloc.free(separator_);
  debugEnd?.call('XCASH_PendingTransaction_txid');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_txid');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_txid', e);
    debugEnd?.call('XCASH_PendingTransaction_txid');
    return "";
  }
}

int PendingTransaction_txCount(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_txCount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txCount = lib!.XCASH_PendingTransaction_txCount(ptr);
  debugEnd?.call('XCASH_PendingTransaction_txCount');
  return txCount;
}

String PendingTransaction_subaddrAccount(
    PendingTransaction ptr, String separator) {
  debugStart?.call('XCASH_PendingTransaction_subaddrAccount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final separator_ = separator.toNativeUtf8().cast<Char>();
  final txid = lib!.XCASH_PendingTransaction_subaddrAccount(ptr, separator_);
  calloc.free(separator_);
  debugEnd?.call('XCASH_PendingTransaction_subaddrAccount');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_subaddrAccount');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_subaddrAccount', e);
    debugEnd?.call('XCASH_PendingTransaction_subaddrAccount');
    return "";
  }
}

String PendingTransaction_subaddrIndices(
    PendingTransaction ptr, String separator) {
  debugStart?.call('XCASH_PendingTransaction_subaddrIndices');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final separator_ = separator.toNativeUtf8().cast<Char>();
  final txid = lib!.XCASH_PendingTransaction_subaddrIndices(ptr, separator_);
  calloc.free(separator_);
  debugEnd?.call('XCASH_PendingTransaction_subaddrIndices');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_subaddrIndices');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_subaddrIndices', e);
    debugEnd?.call('XCASH_PendingTransaction_subaddrIndices');
    return "";
  }
}

String PendingTransaction_multisigSignData(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_multisigSignData');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid = lib!.XCASH_PendingTransaction_multisigSignData(ptr);
  debugEnd?.call('XCASH_PendingTransaction_multisigSignData');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_PendingTransaction_multisigSignData');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_multisigSignData', e);
    debugEnd?.call('XCASH_PendingTransaction_multisigSignData');
    return "";
  }
}

void PendingTransaction_signMultisigTx(PendingTransaction ptr) {
  debugStart?.call('XCASH_PendingTransaction_signMultisigTx');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_PendingTransaction_signMultisigTx(ptr);
  debugEnd?.call('XCASH_PendingTransaction_signMultisigTx');
  return ret;
}

String PendingTransaction_signersKeys(
    PendingTransaction ptr, String separator) {
  debugStart?.call('XCASH_PendingTransaction_signersKeys');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final separator_ = separator.toNativeUtf8().cast<Char>();
  final txid = lib!.XCASH_PendingTransaction_signersKeys(ptr, separator_);
  calloc.free(separator_);
  debugEnd?.call('XCASH_PendingTransaction_signersKeys');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    debugEnd?.call('XCASH_PendingTransaction_signersKeys');
    XCASH_free(strPtr.cast());
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_signersKeys', e);
    debugEnd?.call('XCASH_PendingTransaction_signersKeys');
    return "";
  }
}

String PendingTransaction_hex(PendingTransaction ptr, String separator) {
  debugStart?.call('XCASH_PendingTransaction_hex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final separator_ = separator.toNativeUtf8().cast<Char>();
  final txid = lib!.XCASH_PendingTransaction_hex(ptr, separator_);
  calloc.free(separator_);
  debugEnd?.call('XCASH_PendingTransaction_hex');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    debugEnd?.call('XCASH_PendingTransaction_hex');
    XCASH_free(strPtr.cast());
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_PendingTransaction_hex', e);
    debugEnd?.call('XCASH_PendingTransaction_hex');
    return "";
  }
}

// UnsignedTransaction

typedef UnsignedTransaction = Pointer<Void>;

int UnsignedTransaction_status(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_status');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final dust = lib!.XCASH_UnsignedTransaction_status(ptr);
  debugStart?.call('XCASH_UnsignedTransaction_status');
  return dust;
}

String UnsignedTransaction_errorString(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_errorString');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString = lib!.XCASH_UnsignedTransaction_errorString(ptr);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_errorString');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_errorString', e);
    debugEnd?.call('XCASH_UnsignedTransaction_errorString');
    return "";
  }
}

String UnsignedTransaction_amount(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_amount');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString =
      lib!.XCASH_UnsignedTransaction_amount(ptr, defaultSeparator);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_amount');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_amount', e);
    debugEnd?.call('XCASH_UnsignedTransaction_amount');
    return "";
  }
}

String UnsignedTransaction_fee(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_fee');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString =
      lib!.XCASH_UnsignedTransaction_fee(ptr, defaultSeparator);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_fee');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_fee', e);
    debugEnd?.call('XCASH_UnsignedTransaction_fee');
    return "";
  }
}

String UnsignedTransaction_mixin(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_mixin');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString =
      lib!.XCASH_UnsignedTransaction_mixin(ptr, defaultSeparator);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_mixin');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_mixin', e);
    debugEnd?.call('XCASH_UnsignedTransaction_mixin');
    return "";
  }
}

String UnsignedTransaction_confirmationMessage(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_confirmationMessage');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString = lib!.XCASH_UnsignedTransaction_confirmationMessage(ptr);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_confirmationMessage');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_confirmationMessage', e);
    debugEnd?.call('XCASH_UnsignedTransaction_confirmationMessage');
    return "";
  }
}

String UnsignedTransaction_paymentId(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_paymentId');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString =
      lib!.XCASH_UnsignedTransaction_paymentId(ptr, defaultSeparator);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_paymentId');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_paymentId', e);
    debugEnd?.call('XCASH_UnsignedTransaction_paymentId');
    return "";
  }
}

String UnsignedTransaction_recipientAddress(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_recipientAddress');

  lib ??= XcashC(DynamicLibrary.open(libPath));
  final errorString =
      lib!.XCASH_UnsignedTransaction_recipientAddress(ptr, defaultSeparator);
  try {
    final strPtr = errorString.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_recipientAddress');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_recipientAddress', e);
    debugEnd?.call('XCASH_UnsignedTransaction_recipientAddress');
    return "";
  }
}

int UnsignedTransaction_minMixinCount(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_minMixinCount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_UnsignedTransaction_minMixinCount(ptr);
  debugStart?.call('XCASH_UnsignedTransaction_minMixinCount');
  return v;
}

int UnsignedTransaction_txCount(UnsignedTransaction ptr) {
  debugStart?.call('XCASH_UnsignedTransaction_txCount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_UnsignedTransaction_txCount(ptr);
  debugStart?.call('XCASH_UnsignedTransaction_txCount');
  return v;
}

bool UnsignedTransaction_sign(UnsignedTransaction ptr, String signedFileName) {
  debugStart?.call('XCASH_UnsignedTransaction_sign');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final signedFileName_ = signedFileName.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_UnsignedTransaction_sign(ptr, signedFileName_);
  calloc.free(signedFileName_);
  debugStart?.call('XCASH_UnsignedTransaction_sign');
  return v;
}

String UnsignedTransaction_signUR(
    PendingTransaction ptr, int max_fragment_length) {
  debugStart?.call('XCASH_UnsignedTransaction_signUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid = lib!.XCASH_UnsignedTransaction_signUR(ptr, max_fragment_length);
  debugEnd?.call('XCASH_UnsignedTransaction_signUR');
  try {
    final strPtr = txid.cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_UnsignedTransaction_signUR');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_UnsignedTransaction_signUR', e);
    debugEnd?.call('XCASH_UnsignedTransaction_signUR');
    return "";
  }
}

// TransactionInfo

typedef TransactionInfo = Pointer<Void>;

enum TransactionInfo_Direction { In, Out }

TransactionInfo_Direction TransactionInfo_direction(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_direction');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final tiDir = TransactionInfo_Direction
      .values[lib!.XCASH_TransactionInfo_direction(ptr)];
  debugEnd?.call('XCASH_TransactionInfo_direction');
  return tiDir;
}

bool TransactionInfo_isPending(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_isPending');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final isPending = lib!.XCASH_TransactionInfo_isPending(ptr);
  debugEnd?.call('XCASH_TransactionInfo_isPending');

  return isPending;
}

bool TransactionInfo_isFailed(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_isFailed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final isFailed = lib!.XCASH_TransactionInfo_isFailed(ptr);
  debugEnd?.call('XCASH_TransactionInfo_isFailed');
  return isFailed;
}

bool TransactionInfo_isCoinbase(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_isCoinbase');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final isCoinbase = lib!.XCASH_TransactionInfo_isCoinbase(ptr);
  debugEnd?.call('XCASH_TransactionInfo_isCoinbase');
  return isCoinbase;
}

int TransactionInfo_amount(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_amount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final amount = lib!.XCASH_TransactionInfo_amount(ptr);
  debugEnd?.call('XCASH_TransactionInfo_amount');
  return amount;
}

int TransactionInfo_fee(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_fee');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final fee = lib!.XCASH_TransactionInfo_fee(ptr);
  debugEnd?.call('XCASH_TransactionInfo_fee');
  return fee;
}

int TransactionInfo_blockHeight(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_blockHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final blockHeight = lib!.XCASH_TransactionInfo_blockHeight(ptr);
  debugEnd?.call('XCASH_TransactionInfo_blockHeight');
  return blockHeight;
}

String TransactionInfo_description(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_description');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_TransactionInfo_description(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_description');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_description', e);
    return "";
  }
}

String TransactionInfo_subaddrIndex(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_subaddrIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_TransactionInfo_subaddrIndex(ptr, defaultSeparator)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_subaddrIndex');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_subaddrIndex', e);
    return "";
  }
}

int TransactionInfo_subaddrAccount(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_subaddrAccount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final subaddrAccount = lib!.XCASH_TransactionInfo_subaddrAccount(ptr);
  debugEnd?.call('XCASH_TransactionInfo_subaddrAccount');
  return subaddrAccount;
}

String TransactionInfo_label(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_label');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_TransactionInfo_label(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_label');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_label', e);
    debugEnd?.call('XCASH_TransactionInfo_label');
    return "";
  }
}

int TransactionInfo_confirmations(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_confirmations');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final confirmations = lib!.XCASH_TransactionInfo_confirmations(ptr);
  debugEnd?.call('XCASH_TransactionInfo_confirmations');
  return confirmations;
}

int TransactionInfo_unlockTime(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_unlockTime');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final unlockTime = lib!.XCASH_TransactionInfo_unlockTime(ptr);
  debugEnd?.call('XCASH_TransactionInfo_unlockTime');
  return unlockTime;
}

String TransactionInfo_hash(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_hash');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_TransactionInfo_hash(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_hash');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_hash', e);
    debugEnd?.call('XCASH_TransactionInfo_hash');
    return "";
  }
}

int TransactionInfo_timestamp(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_timestamp');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final timestamp = lib!.XCASH_TransactionInfo_timestamp(ptr);
  debugEnd?.call('XCASH_TransactionInfo_timestamp');
  return timestamp;
}

String TransactionInfo_paymentId(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_paymentId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_TransactionInfo_paymentId(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_paymentId');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_paymentId', e);
    debugEnd?.call('XCASH_TransactionInfo_paymentId');
    return "";
  }
}

int TransactionInfo_transfers_count(TransactionInfo ptr) {
  debugStart?.call('XCASH_TransactionInfo_transfers_count');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_TransactionInfo_transfers_count(ptr);
  debugEnd?.call('XCASH_TransactionInfo_transfers_count');
  return v;
}

int TransactionInfo_transfers_amount(TransactionInfo ptr, int index) {
  debugStart?.call('XCASH_TransactionInfo_transfers_amount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_TransactionInfo_transfers_amount(ptr, index);
  debugEnd?.call('XCASH_TransactionInfo_transfers_amount');
  return v;
}

String TransactionInfo_transfers_address(TransactionInfo ptr, int index) {
  debugStart?.call('XCASH_TransactionInfo_transfers_address');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_TransactionInfo_transfers_address(ptr, index).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_TransactionInfo_transfers_address');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_TransactionInfo_transfers_address', e);
    debugEnd?.call('XCASH_TransactionInfo_transfers_address');
    return "";
  }
}

// TransactionHistory

typedef TransactionHistory = Pointer<Void>;

int TransactionHistory_count(TransactionHistory txHistory_ptr) {
  debugStart?.call('XCASH_TransactionHistory_count');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final count = lib!.XCASH_TransactionHistory_count(txHistory_ptr);
  debugEnd?.call('XCASH_TransactionHistory_count');
  return count;
}

TransactionInfo TransactionHistory_transaction(TransactionHistory txHistory_ptr,
    {required int index}) {
  debugStart?.call('XCASH_TransactionHistory_transaction');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final transaction =
      lib!.XCASH_TransactionHistory_transaction(txHistory_ptr, index);
  debugEnd?.call('XCASH_TransactionHistory_transaction');
  return transaction;
}

TransactionInfo TransactionHistory_transactionById(
    TransactionHistory txHistory_ptr,
    {required String txid}) {
  debugStart?.call('XCASH_TransactionHistory_transactionById');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid_ = txid.toNativeUtf8().cast<Char>();
  final transaction =
      lib!.XCASH_TransactionHistory_transactionById(txHistory_ptr, txid_);
  calloc.free(txid_);
  debugEnd?.call('XCASH_TransactionHistory_transactionById');
  return transaction;
}

void TransactionHistory_refresh(TransactionHistory txHistory_ptr) {
  lib ??= XcashC(DynamicLibrary.open(libPath));
  return lib!.XCASH_TransactionHistory_refresh(txHistory_ptr);
}

void TransactionHistory_setTxNote(TransactionHistory txHistory_ptr,
    {required String txid, required String note}) {
  debugStart?.call('XCASH_TransactionHistory_setTxNote');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid_ = txid.toNativeUtf8().cast<Char>();
  final note_ = note.toNativeUtf8().cast<Char>();
  final s =
      lib!.XCASH_TransactionHistory_setTxNote(txHistory_ptr, txid_, note_);
  calloc.free(txid_);
  calloc.free(note_);
  debugEnd?.call('XCASH_TransactionHistory_setTxNote');
  return s;
}

// AddresBookRow

typedef AddressBookRow = Pointer<Void>;

String AddressBookRow_extra(AddressBookRow addressBookRow_ptr) {
  debugStart?.call('XCASH_AddressBookRow_extra');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_AddressBookRow_extra(addressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_AddressBookRow_extra');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_AddressBookRow_extra', e);
    debugEnd?.call('XCASH_AddressBookRow_extra');
    return "";
  }
}

String AddressBookRow_getAddress(AddressBookRow addressBookRow_ptr) {
  debugStart?.call('XCASH_AddressBookRow_getAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_AddressBookRow_getAddress(addressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_AddressBookRow_getAddress');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_AddressBookRow_getAddress', e);
    debugEnd?.call('XCASH_AddressBookRow_getAddress');
    return "";
  }
}

String AddressBookRow_getDescription(AddressBookRow addressBookRow_ptr) {
  debugStart?.call('XCASH_AddressBookRow_getDescription');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_AddressBookRow_getDescription(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_AddressBookRow_getDescription');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_AddressBookRow_getDescription', e);
    debugEnd?.call('XCASH_AddressBookRow_getDescription');
    return "";
  }
}

String AddressBookRow_getPaymentId(AddressBookRow addressBookRow_ptr) {
  debugStart?.call('XCASH_AddressBookRow_getPaymentId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_AddressBookRow_getPaymentId(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_AddressBookRow_getPaymentId');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_AddressBookRow_getPaymentId', e);
    debugEnd?.call('XCASH_AddressBookRow_getPaymentId');
    return "";
  }
}

int AddressBookRow_getRowId(AddressBookRow addressBookRow_ptr) {
  debugStart?.call('XCASH_AddressBookRow_getRowId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBookRow_getRowId(addressBookRow_ptr);
  debugEnd?.call('XCASH_AddressBookRow_getRowId');
  return v;
}

// AddressBook

typedef AddressBook = Pointer<Void>;

int AddressBook_getAll_size(AddressBook addressBook_ptr) {
  debugStart?.call('XCASH_AddressBook_getAll_size');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBook_getAll_size(addressBook_ptr);
  debugEnd?.call('XCASH_AddressBook_getAll_size');
  return v;
}

AddressBookRow AddressBook_getAll_byIndex(AddressBook addressBook_ptr,
    {required int index}) {
  debugStart?.call('XCASH_AddressBook_getAll_byIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBook_getAll_byIndex(addressBook_ptr, index);
  debugEnd?.call('XCASH_AddressBook_getAll_byIndex');
  return v;
}

bool AddressBook_addRow(
  AddressBook addressBook_ptr, {
  required String dstAddr,
  required String paymentId,
  required String description,
}) {
  debugStart?.call('XCASH_AddressBook_addRow');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final dst_addr_ = dstAddr.toNativeUtf8().cast<Char>();
  final payment_id_ = paymentId.toNativeUtf8().cast<Char>();
  final description_ = description.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_AddressBook_addRow(
      addressBook_ptr, dst_addr_, payment_id_, description_);
  calloc.free(dst_addr_);
  calloc.free(payment_id_);
  calloc.free(description_);
  debugEnd?.call('XCASH_AddressBook_addRow');
  return v;
}

bool AddressBook_deleteRow(AddressBook addressBook_ptr, {required int rowId}) {
  debugStart?.call('XCASH_AddressBook_deleteRow');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBook_deleteRow(addressBook_ptr, rowId);
  debugEnd?.call('XCASH_AddressBook_deleteRow');
  return v;
}

bool AddressBook_setDescription(
  AddressBook addressBook_ptr, {
  required int rowId,
  required String description,
}) {
  debugStart?.call('XCASH_AddressBook_setDescription');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final description_ = description.toNativeUtf8().cast<Char>();
  final v = lib!
      .XCASH_AddressBook_setDescription(addressBook_ptr, rowId, description_);
  calloc.free(description_);
  debugEnd?.call('XCASH_AddressBook_setDescription');
  return v;
}

void AddressBook_refresh(AddressBook addressBook_ptr) {
  debugStart?.call('XCASH_AddressBook_refresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBook_refresh(addressBook_ptr);
  debugEnd?.call('XCASH_AddressBook_refresh');
  return v;
}

int AddressBook_errorCode(AddressBook addressBook_ptr) {
  debugStart?.call('XCASH_AddressBook_errorCode');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_AddressBook_errorCode(addressBook_ptr);
  debugEnd?.call('XCASH_AddressBook_errorCode');
  return v;
}

int AddressBook_lookupPaymentID(AddressBook addressBook_ptr,
    {required String paymentId}) {
  debugStart?.call('XCASH_AddressBook_lookupPaymentID');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final paymentId_ = paymentId.toNativeUtf8().cast<Char>();
  final v =
      lib!.XCASH_AddressBook_lookupPaymentID(addressBook_ptr, paymentId_);
  calloc.free(paymentId_);
  debugEnd?.call('XCASH_AddressBook_lookupPaymentID');
  return v;
}

// CoinsInfo
typedef CoinsInfo = Pointer<Void>;

int CoinsInfo_blockHeight(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_blockHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_blockHeight(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_blockHeight');
  return v;
}

String CoinsInfo_hash(CoinsInfo addressBookRow_ptr) {
  debugStart?.call('XCASH_CoinsInfo_hash');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_CoinsInfo_hash(addressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_hash');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_hash', e);
    debugEnd?.call('XCASH_CoinsInfo_hash');
    return "";
  }
}

int CoinsInfo_internalOutputIndex(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_internalOutputIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_internalOutputIndex(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_internalOutputIndex');
  return v;
}

int CoinsInfo_globalOutputIndex(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_globalOutputIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_globalOutputIndex(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_globalOutputIndex');
  return v;
}

bool CoinsInfo_spent(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_spent');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_spent(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_spent');
  return v;
}

bool CoinsInfo_frozen(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_frozen');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_frozen(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_frozen');
  return v;
}

int CoinsInfo_spentHeight(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_spentHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_spentHeight(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_spentHeight');
  return v;
}

int CoinsInfo_amount(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_amount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_amount(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_amount');
  return v;
}

bool CoinsInfo_rct(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_rct');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_rct(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_rct');
  return v;
}

bool CoinsInfo_keyImageKnown(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_keyImageKnown');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_keyImageKnown(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_keyImageKnown');
  return v;
}

int CoinsInfo_pkIndex(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_pkIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_pkIndex(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_pkIndex');
  return v;
}

int CoinsInfo_subaddrIndex(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_subaddrIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_subaddrIndex(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_subaddrIndex');
  return v;
}

int CoinsInfo_subaddrAccount(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_subaddrAccount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_subaddrAccount(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_subaddrAccount');
  return v;
}

String CoinsInfo_address(CoinsInfo addressBookRow_ptr) {
  debugStart?.call('XCASH_CoinsInfo_address');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_CoinsInfo_address(addressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_address');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_address', e);
    debugEnd?.call('XCASH_CoinsInfo_address');
    return "";
  }
}

String CoinsInfo_addressLabel(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_addressLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_CoinsInfo_addressLabel(coinsInfo_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_addressLabel');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_addressLabel', e);
    debugEnd?.call('XCASH_CoinsInfo_addressLabel');
    return "";
  }
}

String CoinsInfo_keyImage(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_keyImage');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_CoinsInfo_keyImage(coinsInfo_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_keyImage');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_keyImage', e);
    debugEnd?.call('XCASH_CoinsInfo_keyImage');
    return "";
  }
}

int CoinsInfo_unlockTime(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_unlockTime');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_unlockTime(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_unlockTime');
  return v;
}

bool CoinsInfo_unlocked(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_unlocked');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_unlocked(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_unlocked');
  return v;
}

String CoinsInfo_pubKey(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_pubKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_CoinsInfo_pubKey(coinsInfo_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_pubKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_pubKey', e);
    debugEnd?.call('XCASH_CoinsInfo_pubKey');
    return "";
  }
}

bool CoinsInfo_coinbase(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_coinbase');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_CoinsInfo_coinbase(coinsInfo_ptr);
  debugEnd?.call('XCASH_CoinsInfo_coinbase');
  return v;
}

String CoinsInfo_description(CoinsInfo coinsInfo_ptr) {
  debugStart?.call('XCASH_CoinsInfo_description');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_CoinsInfo_description(coinsInfo_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_CoinsInfo_description');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_CoinsInfo_description', e);
    debugEnd?.call('XCASH_CoinsInfo_description');
    return "";
  }
}

typedef Coins = Pointer<Void>;

int Coins_count(Coins coins_ptr) {
  debugStart?.call('XCASH_Coins_count');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_count(coins_ptr);
  debugEnd?.call('XCASH_Coins_count');
  return v;
}

CoinsInfo Coins_coin(Coins coins_ptr, int index) {
  debugStart?.call('XCASH_Coins_coin');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_coin(coins_ptr, index);
  debugEnd?.call('XCASH_Coins_coin');
  return v;
}

int Coins_getAll_size(Coins coins_ptr) {
  debugStart?.call('XCASH_Coins_getAll_size');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_getAll_size(coins_ptr);
  debugEnd?.call('XCASH_Coins_getAll_size');
  return v;
}

CoinsInfo Coins_getAll_byIndex(Coins coins_ptr, int index) {
  debugStart?.call('XCASH_Coins_getAll_byIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_getAll_byIndex(coins_ptr, index);
  debugEnd?.call('XCASH_Coins_getAll_byIndex');
  return v;
}

void Coins_refresh(Coins coins_ptr) {
  debugStart?.call('XCASH_Coins_refresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_refresh(coins_ptr);
  debugEnd?.call('XCASH_Coins_refresh');
  return v;
}

void Coins_setFrozenByPublicKey(Coins coins_ptr, {required String publicKey}) {
  debugStart?.call('XCASH_Coins_setFrozenByPublicKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final publicKey_ = publicKey.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_Coins_setFrozenByPublicKey(coins_ptr, publicKey_);
  calloc.free(publicKey_);
  debugEnd?.call('XCASH_Coins_setFrozenByPublicKey');
  return v;
}

void Coins_setFrozen(Coins coins_ptr, {required int index}) {
  debugStart?.call('XCASH_Coins_setFrozen');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_setFrozen(coins_ptr, index);
  debugEnd?.call('XCASH_Coins_setFrozen');
  return v;
}

void Coins_thaw(Coins coins_ptr, {required int index}) {
  debugStart?.call('XCASH_Coins_thaw');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Coins_thaw(coins_ptr, index);
  debugEnd?.call('XCASH_Coins_thaw');
  return v;
}

void Coins_thawByPublicKey(Coins coins_ptr, {required String publicKey}) {
  debugStart?.call('XCASH_Coins_thawByPublicKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final publicKey_ = publicKey.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_Coins_thawByPublicKey(coins_ptr, publicKey_);
  calloc.free(publicKey_);
  debugEnd?.call('XCASH_Coins_thawByPublicKey');
  return v;
}

bool Coins_isTransferUnlocked(
  Coins coins_ptr, {
  required int unlockTime,
  required int blockHeight,
}) {
  debugStart?.call('XCASH_Coins_isTransferUnlocked');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v =
      lib!.XCASH_Coins_isTransferUnlocked(coins_ptr, unlockTime, blockHeight);
  debugEnd?.call('XCASH_Coins_isTransferUnlocked');
  return v;
}

// SubaddressRow

typedef SubaddressRow = Pointer<Void>;

String SubaddressRow_extra(SubaddressRow subaddressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressRow_extra');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_SubaddressRow_extra(subaddressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressRow_extra');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressRow_extra', e);
    debugEnd?.call('XCASH_SubaddressRow_extra');
    return "";
  }
}

String SubaddressRow_getAddress(SubaddressRow subaddressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressRow_getAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_SubaddressRow_getAddress(subaddressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressRow_getAddress');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressRow_getAddress', e);
    debugEnd?.call('XCASH_SubaddressRow_getAddress');
    return "";
  }
}

String SubaddressRow_getLabel(SubaddressRow subaddressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressRow_getLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_SubaddressRow_getLabel(subaddressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressRow_getLabel');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressRow_getLabel', e);
    debugEnd?.call('XCASH_SubaddressRow_getLabel');
    return "";
  }
}

int SubaddressRow_getRowId(SubaddressRow subaddressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressRow_getRowId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_SubaddressRow_getRowId(subaddressBookRow_ptr);
  debugEnd?.call('XCASH_SubaddressRow_getRowId');
  return status;
}

// Subaddress

typedef Subaddress = Pointer<Void>;

int Subaddress_getAll_size(SubaddressRow subaddressBookRow_ptr) {
  debugStart?.call('XCASH_Subaddress_getAll_size');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Subaddress_getAll_size(subaddressBookRow_ptr);
  debugEnd?.call('XCASH_Subaddress_getAll_size');
  return status;
}

SubaddressRow Subaddress_getAll_byIndex(Subaddress subaddressRow_ptr,
    {required int index}) {
  debugStart?.call('XCASH_Subaddress_getAll_byIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status =
      lib!.XCASH_Subaddress_getAll_byIndex(subaddressRow_ptr, index);
  debugEnd?.call('XCASH_Subaddress_getAll_byIndex');
  return status;
}

void Subaddress_addRow(Subaddress ptr,
    {required int accountIndex, required String label}) {
  debugStart?.call('XCASH_Subaddress_addRow');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final label_ = label.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_Subaddress_addRow(ptr, accountIndex, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_Subaddress_addRow');
  return status;
}

void Subaddress_setLabel(Subaddress ptr,
    {required int accountIndex,
    required int addressIndex,
    required String label}) {
  debugStart?.call('XCASH_Subaddress_setLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final label_ = label.toNativeUtf8().cast<Char>();
  final status =
      lib!.XCASH_Subaddress_setLabel(ptr, accountIndex, addressIndex, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_Subaddress_setLabel');
  return status;
}

void Subaddress_refresh(Subaddress ptr,
    {required int accountIndex, required String label}) {
  debugStart?.call('XCASH_Subaddress_refresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final label_ = label.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_Subaddress_refresh(ptr, accountIndex);
  calloc.free(label_);
  debugEnd?.call('XCASH_Subaddress_refresh');
  return status;
}

typedef SubaddressAccountRow = Pointer<Void>;

String SubaddressAccountRow_extra(SubaddressAccountRow addressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_extra');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr =
        lib!.XCASH_SubaddressAccountRow_extra(addressBookRow_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressAccountRow_extra');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressAccountRow_extra', e);
    debugEnd?.call('XCASH_SubaddressAccountRow_extra');
    return "";
  }
}

String SubaddressAccountRow_getAddress(
    SubaddressAccountRow addressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_getAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_SubaddressAccountRow_getAddress(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressAccountRow_getAddress');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressAccountRow_getAddress', e);
    debugEnd?.call('XCASH_SubaddressAccountRow_getAddress');
    return "";
  }
}

String SubaddressAccountRow_getLabel(SubaddressAccountRow addressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_getLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_SubaddressAccountRow_getLabel(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressAccountRow_getLabel');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressAccountRow_getLabel', e);
    debugEnd?.call('XCASH_SubaddressAccountRow_getLabel');
    return "";
  }
}

String SubaddressAccountRow_getBalance(
    SubaddressAccountRow addressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_getBalance');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_SubaddressAccountRow_getBalance(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressAccountRow_getBalance');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressAccountRow_getBalance', e);
    debugEnd?.call('XCASH_SubaddressAccountRow_getBalance');
    return "";
  }
}

String SubaddressAccountRow_getUnlockedBalance(
    SubaddressAccountRow addressBookRow_ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_getUnlockedBalance');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_SubaddressAccountRow_getUnlockedBalance(addressBookRow_ptr)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_SubaddressAccountRow_getUnlockedBalance');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_SubaddressAccountRow_getUnlockedBalance', e);
    debugEnd?.call('XCASH_SubaddressAccountRow_getUnlockedBalance');
    return "";
  }
}

int SubaddressAccountRow_getRowId(SubaddressAccountRow ptr) {
  debugStart?.call('XCASH_SubaddressAccountRow_getRowId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_SubaddressAccountRow_getRowId(ptr);
  debugEnd?.call('XCASH_SubaddressAccountRow_getRowId');
  return status;
}

typedef SubaddressAccount = Pointer<Void>;

int SubaddressAccount_getAll_size(SubaddressAccount ptr) {
  debugStart?.call('XCASH_SubaddressAccount_getAll_size');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_SubaddressAccount_getAll_size(ptr);
  debugEnd?.call('XCASH_SubaddressAccount_getAll_size');
  return status;
}

SubaddressAccountRow SubaddressAccount_getAll_byIndex(SubaddressAccount ptr,
    {required int index}) {
  debugStart?.call('XCASH_SubaddressAccount_getAll_byIndex');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_SubaddressAccount_getAll_byIndex(ptr, index);
  debugEnd?.call('XCASH_SubaddressAccount_getAll_byIndex');
  return status;
}

void SubaddressAccount_addRow(SubaddressAccount ptr, {required String label}) {
  debugStart?.call('XCASH_SubaddressAccount_addRow');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final label_ = label.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_SubaddressAccount_addRow(ptr, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_SubaddressAccount_addRow');
  return status;
}

void SubaddressAccount_setLabel(SubaddressAccount ptr,
    {required int accountIndex, required String label}) {
  debugStart?.call('XCASH_SubaddressAccount_setLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final label_ = label.toNativeUtf8().cast<Char>();
  final status =
      lib!.XCASH_SubaddressAccount_setLabel(ptr, accountIndex, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_SubaddressAccount_setLabel');
  return status;
}

void SubaddressAccount_refresh(SubaddressAccount ptr) {
  debugStart?.call('XCASH_SubaddressAccount_refresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_SubaddressAccount_refresh(ptr);
  debugEnd?.call('XCASH_SubaddressAccount_refresh');
  return status;
}

// MultisigState

typedef MultisigState = Pointer<Void>;

bool MultisigState_isMultisig(MultisigState ptr) {
  debugStart?.call('XCASH_MultisigState_isMultisig');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_MultisigState_isMultisig(ptr);
  debugEnd?.call('XCASH_MultisigState_isMultisig');
  return status;
}

bool MultisigState_isReady(MultisigState ptr) {
  debugStart?.call('XCASH_MultisigState_isReady');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_MultisigState_isReady(ptr);
  debugEnd?.call('XCASH_MultisigState_isReady');
  return status;
}

int MultisigState_threshold(MultisigState ptr) {
  debugStart?.call('XCASH_MultisigState_threshold');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_MultisigState_threshold(ptr);
  debugEnd?.call('XCASH_MultisigState_threshold');
  return status;
}

int MultisigState_total(MultisigState ptr) {
  debugStart?.call('XCASH_MultisigState_total');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_MultisigState_total(ptr);
  debugEnd?.call('XCASH_MultisigState_total');
  return status;
}

// DeviceProgress

typedef DeviceProgress = Pointer<Void>;

bool DeviceProgress_progress(DeviceProgress ptr) {
  debugStart?.call('XCASH_DeviceProgress_progress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_DeviceProgress_progress(ptr);
  debugEnd?.call('XCASH_DeviceProgress_progress');
  return status;
}

bool DeviceProgress_indeterminate(DeviceProgress ptr) {
  debugStart?.call('XCASH_DeviceProgress_indeterminate');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_DeviceProgress_indeterminate(ptr);
  debugEnd?.call('XCASH_DeviceProgress_indeterminate');
  return status;
}
// Wallet

typedef wallet = Pointer<Void>;

String Wallet_seed(wallet ptr, {required String seedOffset}) {
  debugStart?.call('XCASH_Wallet_seed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final seedOffset_ = seedOffset.toNativeUtf8().cast<Char>();
    final strPtr = lib!.XCASH_Wallet_seed(ptr, seedOffset_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(seedOffset_);
    debugEnd?.call('XCASH_Wallet_seed');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_seed', e);
    debugEnd?.call('XCASH_Wallet_seed');
    return "";
  }
}

String Wallet_getSeedLanguage(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getSeedLanguage');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_getSeedLanguage(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_getSeedLanguage');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getSeedLanguage', e);
    debugEnd?.call('XCASH_Wallet_getSeedLanguage');
    return "";
  }
}

void Wallet_setSeedLanguage(wallet ptr, {required String language}) {
  debugStart?.call('XCASH_Wallet_setSeedLanguage');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final language_ = language.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_Wallet_setSeedLanguage(ptr, language_);
  calloc.free(language_);
  debugEnd?.call('XCASH_Wallet_setSeedLanguage');
  return status;
}

int Wallet_status(wallet ptr) {
  debugStart?.call('XCASH_Wallet_status');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_status(ptr);
  debugEnd?.call('XCASH_Wallet_status');
  return status;
}

String Wallet_errorString(wallet ptr) {
  debugStart?.call('XCASH_Wallet_errorString');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_errorString(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_errorString');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_errorString', e);
    debugEnd?.call('XCASH_Wallet_errorString');
    return "";
  }
}

bool Wallet_setPassword(wallet ptr, {required String password}) {
  debugStart?.call('XCASH_Wallet_setPassword');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final password_ = password.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_Wallet_setPassword(ptr, password_);
  calloc.free(password_);
  debugEnd?.call('XCASH_Wallet_setPassword');
  return status;
}

String Wallet_getPassword(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getPassword');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_getPassword(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_getPassword');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getPassword', e);
    debugEnd?.call('XCASH_Wallet_getPassword');
    return "";
  }
}

bool Wallet_setDevicePin(wallet ptr, {required String passphrase}) {
  debugStart?.call('XCASH_Wallet_setDevicePin');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final passphrase_ = passphrase.toNativeUtf8().cast<Char>();
  final status = lib!.XCASH_Wallet_setDevicePin(ptr, passphrase_);
  calloc.free(passphrase_);
  debugEnd?.call('XCASH_Wallet_setDevicePin');
  return status;
}

String Wallet_address(wallet ptr,
    {int accountIndex = 0, int addressIndex = 0}) {
  debugStart?.call('XCASH_Wallet_address');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_Wallet_address(ptr, accountIndex, addressIndex)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_address');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_address', e);
    debugEnd?.call('XCASH_Wallet_address');
    return "";
  }
}

String Wallet_path(wallet ptr) {
  debugStart?.call('XCASH_Wallet_path');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_path(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_path');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_path', e);
    debugEnd?.call('XCASH_Wallet_path');
    return "";
  }
}

int Wallet_nettype(wallet ptr) {
  debugStart?.call('XCASH_Wallet_nettype');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_nettype(ptr);
  debugEnd?.call('XCASH_Wallet_nettype');
  return status;
}

int Wallet_useForkRules(
  wallet ptr, {
  required int version,
  required int earlyBlocks,
}) {
  debugStart?.call('XCASH_Wallet_useForkRules');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_useForkRules(ptr, version, earlyBlocks);
  debugEnd?.call('XCASH_Wallet_useForkRules');
  return status;
}

String Wallet_integratedAddress(wallet ptr, {required String paymentId}) {
  debugStart?.call('XCASH_Wallet_integratedAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final paymentId_ = paymentId.toNativeUtf8().cast<Char>();
    final strPtr =
        lib!.XCASH_Wallet_integratedAddress(ptr, paymentId_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_integratedAddress');
    calloc.free(paymentId_);
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_integratedAddress', e);
    debugEnd?.call('XCASH_Wallet_integratedAddress');
    return "";
  }
}

String Wallet_secretViewKey(wallet ptr) {
  debugStart?.call('XCASH_Wallet_secretViewKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_secretViewKey(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_secretViewKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_secretViewKey', e);
    debugEnd?.call('XCASH_Wallet_secretViewKey');
    return "";
  }
}

String Wallet_publicViewKey(wallet ptr) {
  debugStart?.call('XCASH_Wallet_publicViewKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_publicViewKey(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_publicViewKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_publicViewKey', e);
    debugEnd?.call('XCASH_Wallet_publicViewKey');
    return "";
  }
}

String Wallet_secretSpendKey(wallet ptr) {
  debugStart?.call('XCASH_Wallet_secretSpendKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_secretSpendKey(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_secretSpendKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_secretSpendKey', e);
    debugEnd?.call('XCASH_Wallet_secretSpendKey');
    return "";
  }
}

String Wallet_publicSpendKey(wallet ptr) {
  debugStart?.call('XCASH_Wallet_publicSpendKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_publicSpendKey(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_publicSpendKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_publicSpendKey', e);
    debugEnd?.call('XCASH_Wallet_publicSpendKey');
    return "";
  }
}

String Wallet_publicMultisigSignerKey(wallet ptr) {
  debugStart?.call('XCASH_Wallet_publicMultisigSignerKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_publicMultisigSignerKey(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_publicMultisigSignerKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_publicMultisigSignerKey', e);
    debugEnd?.call('XCASH_Wallet_publicMultisigSignerKey');
    return "";
  }
}

void Wallet_stop(wallet ptr) {
  debugStart?.call('XCASH_Wallet_stop');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final stop = lib!.XCASH_Wallet_stop(ptr);
  debugEnd?.call('XCASH_Wallet_stop');
  return stop;
}

bool Wallet_store(wallet ptr, {String path = ""}) {
  debugStart?.call('XCASH_Wallet_store');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_store(ptr, path_);
  calloc.free(path_);
  debugEnd?.call('XCASH_Wallet_store');
  return s;
}

String Wallet_filename(wallet ptr) {
  debugStart?.call('XCASH_Wallet_filename');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_filename(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_filename');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_filename', e);
    debugEnd?.call('XCASH_Wallet_filename');
    return "";
  }
}

String Wallet_keysFilename(wallet ptr) {
  debugStart?.call('XCASH_Wallet_keysFilename');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_keysFilename(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_keysFilename');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_keysFilename', e);
    debugEnd?.call('XCASH_Wallet_keysFilename');
    return "";
  }
}

bool Wallet_init(
  wallet ptr, {
  required String daemonAddress,
  int upperTransacationSizeLimit = 0,
  String daemonUsername = "",
  String daemonPassword = "",
  bool useSsl = false,
  bool lightWallet = false,
  String proxyAddress = "",
}) {
  debugStart?.call('XCASH_Wallet_init');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final daemonAddress_ = daemonAddress.toNativeUtf8().cast<Char>();
  final daemonUsername_ = daemonUsername.toNativeUtf8().cast<Char>();
  final daemonPassword_ = daemonPassword.toNativeUtf8().cast<Char>();
  final proxyAddress_ = proxyAddress.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_init(
      ptr,
      daemonAddress_,
      upperTransacationSizeLimit,
      daemonUsername_,
      daemonPassword_,
      useSsl,
      lightWallet,
      proxyAddress_);

  calloc.free(daemonAddress_);
  calloc.free(daemonUsername_);
  calloc.free(daemonPassword_);
  calloc.free(proxyAddress_);
  debugEnd?.call('XCASH_Wallet_init');
  return s;
}

bool Wallet_createWatchOnly(
  wallet ptr, {
  required String path,
  required String password,
  required String language,
}) {
  debugStart?.call('XCASH_Wallet_createWatchOnly');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final language_ = language.toNativeUtf8().cast<Char>();
  final getRefreshFromBlockHeight =
      lib!.XCASH_Wallet_createWatchOnly(ptr, path_, password_, language_);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(language_);
  debugEnd?.call('XCASH_Wallet_createWatchOnly');
  return getRefreshFromBlockHeight;
}

void Wallet_setRefreshFromBlockHeight(wallet ptr,
    {required int refresh_from_block_height}) {
  debugStart?.call('XCASH_Wallet_setRefreshFromBlockHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!
      .XCASH_Wallet_setRefreshFromBlockHeight(ptr, refresh_from_block_height);
  debugEnd?.call('XCASH_Wallet_setRefreshFromBlockHeight');
  return status;
}

int Wallet_getRefreshFromBlockHeight(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getRefreshFromBlockHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final getRefreshFromBlockHeight =
      lib!.XCASH_Wallet_getRefreshFromBlockHeight(ptr);
  debugEnd?.call('XCASH_Wallet_getRefreshFromBlockHeight');
  return getRefreshFromBlockHeight;
}

void Wallet_setRecoveringFromSeed(wallet ptr,
    {required bool recoveringFromSeed}) {
  debugStart?.call('XCASH_Wallet_setRecoveringFromSeed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status =
      lib!.XCASH_Wallet_setRecoveringFromSeed(ptr, recoveringFromSeed);
  debugEnd?.call('XCASH_Wallet_setRecoveringFromSeed');
  return status;
}

void Wallet_setRecoveringFromDevice(wallet ptr,
    {required bool recoveringFromDevice}) {
  debugStart?.call('XCASH_Wallet_setRecoveringFromDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status =
      lib!.XCASH_Wallet_setRecoveringFromDevice(ptr, recoveringFromDevice);
  debugEnd?.call('XCASH_Wallet_setRecoveringFromDevice');
  return status;
}

void Wallet_setSubaddressLookahead(wallet ptr,
    {required int major, required int minor}) {
  debugStart?.call('XCASH_Wallet_setSubaddressLookahead');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_setSubaddressLookahead(ptr, major, minor);
  debugEnd?.call('XCASH_Wallet_setSubaddressLookahead');
  return status;
}

bool Wallet_connectToDaemon(wallet ptr) {
  debugStart?.call('XCASH_Wallet_connectToDaemon');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final connectToDaemon = lib!.XCASH_Wallet_connectToDaemon(ptr);
  debugEnd?.call('XCASH_Wallet_connectToDaemon');
  return connectToDaemon;
}

int Wallet_connected(wallet ptr) {
  debugStart?.call('XCASH_Wallet_connected');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final connected = lib!.XCASH_Wallet_connected(ptr);
  debugEnd?.call('XCASH_Wallet_connected');
  return connected;
}

void Wallet_setTrustedDaemon(wallet ptr, {required bool arg}) {
  debugStart?.call('XCASH_Wallet_setTrustedDaemon');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_setTrustedDaemon(ptr, arg);
  debugEnd?.call('XCASH_Wallet_setTrustedDaemon');
  return status;
}

bool Wallet_trustedDaemon(wallet ptr) {
  debugStart?.call('XCASH_Wallet_trustedDaemon');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final status = lib!.XCASH_Wallet_trustedDaemon(ptr);
  debugEnd?.call('XCASH_Wallet_trustedDaemon');
  return status;
}

bool Wallet_setProxy(wallet ptr, {required String address}) {
  debugStart?.call('XCASH_Wallet_setProxy');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_setProxy(ptr, address_);
  calloc.free(address_);
  debugEnd?.call('XCASH_Wallet_setProxy');
  return s;
}

int Wallet_balance(wallet ptr, {required int accountIndex}) {
  debugStart?.call('XCASH_Wallet_balance');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final balance = lib!.XCASH_Wallet_balance(ptr, accountIndex);
  debugEnd?.call('XCASH_Wallet_balance');
  return balance;
}

int Wallet_unlockedBalance(wallet ptr, {required int accountIndex}) {
  debugStart?.call('XCASH_Wallet_unlockedBalance');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final unlockedBalance = lib!.XCASH_Wallet_unlockedBalance(ptr, accountIndex);
  debugEnd?.call('XCASH_Wallet_unlockedBalance');
  return unlockedBalance;
}

int Wallet_viewOnlyBalance(wallet ptr, {required int accountIndex}) {
  debugStart?.call('XCASH_Wallet_viewOnlyBalance');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final unlockedBalance = lib!.XCASH_Wallet_viewOnlyBalance(ptr, accountIndex);
  debugEnd?.call('XCASH_Wallet_viewOnlyBalance');
  return unlockedBalance;
}

bool Wallet_watchOnly(wallet ptr) {
  debugStart?.call('XCASH_Wallet_watchOnly');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final watchOnly = lib!.XCASH_Wallet_watchOnly(ptr);
  debugEnd?.call('XCASH_Wallet_watchOnly');
  return watchOnly;
}

int Wallet_blockChainHeight(wallet ptr) {
  debugStart?.call('XCASH_Wallet_blockChainHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final blockChainHeight = lib!.XCASH_Wallet_blockChainHeight(ptr);
  debugEnd?.call('XCASH_Wallet_blockChainHeight');
  return blockChainHeight;
}

int Wallet_approximateBlockChainHeight(wallet ptr) {
  debugStart?.call('XCASH_Wallet_approximateBlockChainHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final approximateBlockChainHeight =
      lib!.XCASH_Wallet_approximateBlockChainHeight(ptr);
  debugEnd?.call('XCASH_Wallet_approximateBlockChainHeight');
  return approximateBlockChainHeight;
}

int Wallet_estimateBlockChainHeight(wallet ptr) {
  debugStart?.call('XCASH_Wallet_estimateBlockChainHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final estimateBlockChainHeight =
      lib!.XCASH_Wallet_estimateBlockChainHeight(ptr);
  debugEnd?.call('XCASH_Wallet_estimateBlockChainHeight');
  return estimateBlockChainHeight;
}

int Wallet_daemonBlockChainHeight(wallet ptr) {
  debugStart?.call('XCASH_Wallet_daemonBlockChainHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final daemonBlockChainHeight = lib!.XCASH_Wallet_daemonBlockChainHeight(ptr);
  debugEnd?.call('XCASH_Wallet_daemonBlockChainHeight');
  return daemonBlockChainHeight;
}

int Wallet_daemonBlockChainHeight_cached(wallet ptr) {
  debugStart?.call('XCASH_Wallet_daemonBlockChainHeight_cached');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final daemonBlockChainHeight =
      lib!.XCASH_Wallet_daemonBlockChainHeight_cached(ptr);
  debugEnd?.call('XCASH_Wallet_daemonBlockChainHeight_cached');
  return daemonBlockChainHeight;
}

void Wallet_daemonBlockChainHeight_runThread(wallet ptr, int seconds) {
  debugStart?.call('XCASH_Wallet_daemonBlockChainHeight_enableRefresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_daemonBlockChainHeight_runThread(ptr, seconds);
  debugEnd?.call('XCASH_Wallet_daemonBlockChainHeight_enableRefresh');
  return ret;
}

bool Wallet_synchronized(wallet ptr) {
  debugStart?.call('XCASH_Wallet_synchronized');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final synchronized = lib!.XCASH_Wallet_synchronized(ptr);
  debugEnd?.call('XCASH_Wallet_synchronized');
  return synchronized;
}

String Wallet_displayAmount(int amount) {
  debugStart?.call('XCASH_Wallet_displayAmount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_displayAmount(amount).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_displayAmount');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_displayAmount', e);
    debugEnd?.call('XCASH_Wallet_displayAmount');
    return "";
  }
}

int Wallet_amountFromString(String amount) {
  debugStart?.call('XCASH_Wallet_amountFromString');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final amount_ = amount.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_amountFromString(amount_);
  calloc.free(amount_);
  debugEnd?.call('XCASH_Wallet_amountFromString');
  return s;
}

int Wallet_amountFromDouble(double amount) {
  debugStart?.call('XCASH_Wallet_amountFromDouble');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_Wallet_amountFromDouble(amount);
  debugEnd?.call('XCASH_Wallet_amountFromDouble');
  return s;
}

String Wallet_genPaymentId() {
  debugStart?.call('XCASH_Wallet_genPaymentId');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_genPaymentId().cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_genPaymentId');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_genPaymentId', e);
    debugEnd?.call('XCASH_Wallet_genPaymentId');
    return "";
  }
}

bool Wallet_paymentIdValid(String paymentId) {
  debugStart?.call('XCASH_Wallet_paymentIdValid');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final paymentId_ = paymentId.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_paymentIdValid(paymentId_);
  calloc.free(paymentId_);
  debugEnd?.call('XCASH_Wallet_paymentIdValid');
  return s;
}

bool Wallet_addressValid(String address, int networkType) {
  debugStart?.call('XCASH_Wallet_addressValid');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_addressValid(address_, networkType);
  calloc.free(address_);
  debugEnd?.call('XCASH_Wallet_addressValid');
  return s;
}

bool Wallet_keyValid(
    {required String secret_key_string,
    required String address_string,
    required bool isViewKey,
    required int nettype}) {
  debugStart?.call('XCASH_Wallet_keyValid');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final secret_key_string_ = secret_key_string.toNativeUtf8().cast<Char>();
  final address_string_ = address_string.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_keyValid(
      secret_key_string_, address_string_, isViewKey, nettype);
  calloc.free(secret_key_string_);
  calloc.free(address_string_);
  debugEnd?.call('XCASH_Wallet_keyValid');
  return s;
}

String Wallet_keyValid_error(
    {required String secret_key_string,
    required String address_string,
    required bool isViewKey,
    required int nettype}) {
  debugStart?.call('XCASH_Wallet_keyValid_error');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final secret_key_string_ = secret_key_string.toNativeUtf8().cast<Char>();
    final address_string_ = address_string.toNativeUtf8().cast<Char>();
    final strPtr = lib!
        .XCASH_Wallet_keyValid_error(
            secret_key_string_, address_string_, isViewKey, nettype)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(secret_key_string_);
    calloc.free(address_string_);
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_keyValid_error', e);
    debugEnd?.call('XCASH_Wallet_keyValid_error');
    return "";
  }
}

String Wallet_paymentIdFromAddress(
    {required String strarg, required int nettype}) {
  debugStart?.call('XCASH_Wallet_paymentIdFromAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strarg_ = strarg.toNativeUtf8().cast<Char>();
    final strPtr =
        lib!.XCASH_Wallet_paymentIdFromAddress(strarg_, nettype).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(strarg_);
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_paymentIdFromAddress', e);
    debugEnd?.call('XCASH_Wallet_paymentIdFromAddress');
    return "";
  }
}

int Wallet_maximumAllowedAmount() {
  debugStart?.call('XCASH_Wallet_maximumAllowedAmount');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_Wallet_maximumAllowedAmount();
  debugEnd?.call('XCASH_Wallet_maximumAllowedAmount');
  return s;
}

void Wallet_init3(
  wallet ptr, {
  required String argv0,
  required String defaultLogBaseName,
  required String logPath,
  required bool console,
}) {
  debugStart?.call('XCASH_Wallet_init3');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final argv0_ = argv0.toNativeUtf8().cast<Char>();
  final defaultLogBaseName_ = defaultLogBaseName.toNativeUtf8().cast<Char>();
  final logPath_ = logPath.toNativeUtf8().cast<Char>();
  final s = lib!
      .XCASH_Wallet_init3(ptr, argv0_, defaultLogBaseName_, logPath_, console);
  calloc.free(argv0_);
  calloc.free(defaultLogBaseName_);
  calloc.free(logPath_);
  debugEnd?.call('XCASH_Wallet_init3');
  return s;
}

String Wallet_getPolyseed(wallet ptr, {required String passphrase}) {
  debugStart?.call('XCASH_Wallet_getPolyseed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final passphrase_ = passphrase.toNativeUtf8().cast<Char>();
    final strPtr =
        lib!.XCASH_Wallet_getPolyseed(ptr, passphrase_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(passphrase_);
    debugEnd?.call('XCASH_Wallet_getPolyseed');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getPolyseed', e);
    debugEnd?.call('XCASH_Wallet_getPolyseed');
    return "";
  }
}

String Wallet_createPolyseed({
  String language = "English",
}) {
  debugStart?.call('XCASH_Wallet_createPolyseed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final language_ = language.toNativeUtf8();
    final strPtr =
        lib!.XCASH_Wallet_createPolyseed(language_.cast()).cast<Utf8>();
    calloc.free(language_);
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_createPolyseed');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_createPolyseed', e);
    debugEnd?.call('XCASH_Wallet_createPolyseed');
    return "";
  }
}

void Wallet_startRefresh(wallet ptr) {
  debugStart?.call('XCASH_Wallet_startRefresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final startRefresh = lib!.XCASH_Wallet_startRefresh(ptr);
  debugEnd?.call('XCASH_Wallet_startRefresh');
  return startRefresh;
}

void Wallet_pauseRefresh(wallet ptr) {
  debugStart?.call('XCASH_Wallet_pauseRefresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final pauseRefresh = lib!.XCASH_Wallet_pauseRefresh(ptr);
  debugEnd?.call('XCASH_Wallet_pauseRefresh');
  return pauseRefresh;
}

bool Wallet_refresh(wallet ptr) {
  debugStart?.call('XCASH_Wallet_refresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final refresh = lib!.XCASH_Wallet_refresh(ptr);
  debugEnd?.call('XCASH_Wallet_refresh');
  return refresh;
}

void Wallet_refreshAsync(wallet ptr) {
  debugStart?.call('XCASH_Wallet_refreshAsync');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final refreshAsync = lib!.XCASH_Wallet_refreshAsync(ptr);
  debugEnd?.call('XCASH_Wallet_refreshAsync');
  return refreshAsync;
}

bool Wallet_rescanBlockchain(wallet ptr) {
  debugStart?.call('XCASH_Wallet_rescanBlockchain');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final rescanBlockchain = lib!.XCASH_Wallet_rescanBlockchain(ptr);
  debugEnd?.call('XCASH_Wallet_rescanBlockchain');
  return rescanBlockchain;
}

void Wallet_rescanBlockchainAsync(wallet ptr) {
  debugStart?.call('XCASH_Wallet_rescanBlockchainAsync');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final rescanBlockchainAsync = lib!.XCASH_Wallet_rescanBlockchainAsync(ptr);
  debugEnd?.call('XCASH_Wallet_rescanBlockchainAsync');
  return rescanBlockchainAsync;
}

void Wallet_setAutoRefreshInterval(wallet ptr, {required int millis}) {
  debugStart?.call('XCASH_Wallet_setAutoRefreshInterval');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final setAutoRefreshInterval =
      lib!.XCASH_Wallet_setAutoRefreshInterval(ptr, millis);
  debugEnd?.call('XCASH_Wallet_setAutoRefreshInterval');
  return setAutoRefreshInterval;
}

int Wallet_autoRefreshInterval(wallet ptr) {
  debugStart?.call('XCASH_Wallet_autoRefreshInterval');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final autoRefreshInterval = lib!.XCASH_Wallet_autoRefreshInterval(ptr);
  debugEnd?.call('XCASH_Wallet_autoRefreshInterval');
  return autoRefreshInterval;
}

void Wallet_addSubaddress(wallet ptr,
    {required int accountIndex, String label = ""}) {
  debugStart?.call('XCASH_Wallet_addSubaddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final label_ = label.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_addSubaddress(ptr, accountIndex, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_Wallet_addSubaddress');
  return s;
}

void Wallet_addSubaddressAccount(wallet ptr, {String label = ""}) {
  debugStart?.call('XCASH_Wallet_addSubaddressAccount');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final label_ = label.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_addSubaddressAccount(ptr, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_Wallet_addSubaddressAccount');
  return s;
}

int Wallet_numSubaddressAccounts(wallet ptr) {
  debugStart?.call('XCASH_Wallet_numSubaddressAccounts');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final numSubaddressAccounts = lib!.XCASH_Wallet_numSubaddressAccounts(ptr);
  debugEnd?.call('XCASH_Wallet_numSubaddressAccounts');
  return numSubaddressAccounts;
}

int Wallet_numSubaddresses(wallet ptr, {required int accountIndex}) {
  debugStart?.call('XCASH_Wallet_numSubaddresses');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final numSubaddresses = lib!.XCASH_Wallet_numSubaddresses(ptr, accountIndex);
  debugEnd?.call('XCASH_Wallet_numSubaddresses');
  return numSubaddresses;
}

String Wallet_getSubaddressLabel(wallet ptr,
    {required int accountIndex, required int addressIndex}) {
  debugStart?.call('XCASH_Wallet_getSubaddressLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_Wallet_getSubaddressLabel(ptr, accountIndex, addressIndex)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_getSubaddressLabel');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getSubaddressLabel', e);
    debugEnd?.call('XCASH_Wallet_getSubaddressLabel');
    return "";
  }
}

void Wallet_setSubaddressLabel(wallet ptr,
    {required int accountIndex,
    required int addressIndex,
    required String label}) {
  debugStart?.call('XCASH_Wallet_setSubaddressLabel');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final label_ = label.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_setSubaddressLabel(
      ptr, accountIndex, addressIndex, label_);
  calloc.free(label_);
  debugEnd?.call('XCASH_Wallet_setSubaddressLabel');
  return s;
}

MultisigState Wallet_multisig(wallet ptr) {
  debugStart?.call('XCASH_Wallet_multisig');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_Wallet_multisig(ptr);
  debugEnd?.call('XCASH_Wallet_multisig');
  return s;
}

String Wallet_getMultisigInfo(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getMultisigInfo');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_Wallet_getMultisigInfo(ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_getMultisigInfo');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getMultisigInfo', e);
    debugEnd?.call('XCASH_Wallet_getMultisigInfo');
    return "";
  }
}

String Wallet_makeMultisig(
  wallet ptr, {
  required List<String> info,
  required int threshold,
}) {
  debugStart?.call('XCASH_Wallet_makeMultisig');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final infoStr = info.join(defaultSeparatorStr).toNativeUtf8();
    final strPtr = lib!
        .XCASH_Wallet_makeMultisig(
          ptr,
          infoStr.cast(),
          defaultSeparator.cast(),
          threshold,
        )
        .cast<Utf8>();
    final str = strPtr.toDartString();
    calloc.free(infoStr);
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_makeMultisig');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_makeMultisig', e);
    debugEnd?.call('XCASH_Wallet_makeMultisig');
    return "";
  }
}

String Wallet_exchangeMultisigKeys(
  wallet ptr, {
  required List<String> info,
  required bool force_update_use_with_caution,
}) {
  debugStart?.call('XCASH_Wallet_exchangeMultisigKeys');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final infoStr = info.join(defaultSeparatorStr).toNativeUtf8();
    final strPtr = lib!
        .XCASH_Wallet_exchangeMultisigKeys(
          ptr,
          infoStr.cast(),
          defaultSeparator.cast(),
          force_update_use_with_caution,
        )
        .cast<Utf8>();
    final str = strPtr.toDartString();
    calloc.free(infoStr);
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_exchangeMultisigKeys');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_exchangeMultisigKeys', e);
    debugEnd?.call('XCASH_Wallet_exchangeMultisigKeys');
    return "";
  }
}

List<String> Wallet_exportMultisigImages(
  wallet ptr, {
  required List<String> info,
  required bool force_update_use_with_caution,
}) {
  debugStart?.call('XCASH_Wallet_exportMultisigImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final infoStr = info.join(defaultSeparatorStr).toNativeUtf8();
    final strPtr = lib!
        .XCASH_Wallet_exportMultisigImages(
          ptr,
          defaultSeparator.cast(),
        )
        .cast<Utf8>();
    final str = strPtr.toDartString();
    calloc.free(infoStr);
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_exportMultisigImages');
    return str.split(defaultSeparatorStr);
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_exportMultisigImages', e);
    debugEnd?.call('XCASH_Wallet_exportMultisigImages');
    return [];
  }
}

int Wallet_importMultisigImages(
  wallet ptr, {
  required List<String> info,
}) {
  debugStart?.call('XCASH_Wallet_importMultisigImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final infoStr = info.join(defaultSeparatorStr).toNativeUtf8();
  final ret = lib!.XCASH_Wallet_importMultisigImages(
    ptr,
    infoStr.cast(),
    defaultSeparator.cast(),
  );
  calloc.free(infoStr);
  debugEnd?.call('XCASH_Wallet_importMultisigImages');
  return ret;
}

int Wallet_hasMultisigPartialKeyImages(wallet ptr) {
  debugStart?.call('XCASH_Wallet_hasMultisigPartialKeyImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_hasMultisigPartialKeyImages(
    ptr,
  );
  debugEnd?.call('XCASH_Wallet_hasMultisigPartialKeyImages');
  return ret;
}

PendingTransaction Wallet_restoreMultisigTransaction(
  wallet ptr, {
  required String signData,
}) {
  debugStart?.call('XCASH_Wallet_restoreMultisigTransaction');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final signData_ = signData.toNativeUtf8();
  final ret = lib!.XCASH_Wallet_restoreMultisigTransaction(
    ptr,
    signData_.cast(),
  );
  calloc.free(signData_);
  debugEnd?.call('XCASH_Wallet_restoreMultisigTransaction');
  return ret;
}

PendingTransaction Wallet_createTransactionMultDest(
  wallet wptr, {
  required List<String> dstAddr,
  String paymentId = "",
  required bool isSweepAll,
  required List<int> amounts,
  required int mixinCount,
  required int pendingTransactionPriority,
  required int subaddr_account,
  List<String> preferredInputs = const [],
}) {
  debugStart?.call('XCASH_Wallet_createTransactionMultDest');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final dst_addr_list = dstAddr.join(defaultSeparatorStr).toNativeUtf8();
  final payment_id = paymentId.toNativeUtf8();
  final amount_list =
      amounts.map((e) => e.toString()).join(defaultSeparatorStr).toNativeUtf8();
  final preferredInputs_ =
      preferredInputs.join(defaultSeparatorStr).toNativeUtf8();
  final ret = lib!.XCASH_Wallet_createTransactionMultDest(
    wptr,
    dst_addr_list.cast(),
    defaultSeparator,
    payment_id.cast(),
    isSweepAll,
    amount_list.cast(),
    defaultSeparator,
    mixinCount,
    pendingTransactionPriority,
    subaddr_account,
    preferredInputs_.cast(),
    defaultSeparator,
  );
  calloc.free(dst_addr_list);
  calloc.free(payment_id);
  calloc.free(amount_list);
  calloc.free(preferredInputs_);
  debugEnd?.call('XCASH_Wallet_createTransactionMultDest');
  return ret;
}

PendingTransaction Wallet_createTransaction(wallet ptr,
    {required String dst_addr,
    required String payment_id,
    required int amount,
    required int mixin_count,
    required int pendingTransactionPriority,
    required int subaddr_account,
    List<String> preferredInputs = const []}) {
  debugStart?.call('XCASH_Wallet_createTransaction');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final dst_addr_ = dst_addr.toNativeUtf8().cast<Char>();
  final payment_id_ = payment_id.toNativeUtf8().cast<Char>();
  final preferredInputs_ =
      preferredInputs.join(defaultSeparatorStr).toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_createTransaction(
    ptr,
    dst_addr_,
    payment_id_,
    amount,
    mixin_count,
    pendingTransactionPriority,
    subaddr_account,
    preferredInputs_,
    defaultSeparator,
  );
  calloc.free(dst_addr_);
  calloc.free(payment_id_);
  calloc.free(preferredInputs_);
  debugEnd?.call('XCASH_Wallet_createTransaction');
  return s;
}

UnsignedTransaction Wallet_loadUnsignedTx(wallet ptr,
    {required String unsigned_filename}) {
  debugStart?.call('XCASH_Wallet_loadUnsignedTx');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final unsigned_filename_ = unsigned_filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_loadUnsignedTx(ptr, unsigned_filename_);
  calloc.free(unsigned_filename_);
  debugEnd?.call('XCASH_Wallet_loadUnsignedTx');
  return s;
}

UnsignedTransaction Wallet_loadUnsignedTxUR(wallet ptr,
    {required String input}) {
  debugStart?.call('XCASH_Wallet_loadUnsignedTxUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final input_ = input.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_loadUnsignedTxUR(ptr, input_);
  calloc.free(input_);
  debugEnd?.call('XCASH_Wallet_loadUnsignedTxUR');
  return s;
}

bool Wallet_submitTransaction(wallet ptr, String filename) {
  debugStart?.call('XCASH_Wallet_submitTransaction');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final filename_ = filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_submitTransaction(ptr, filename_);
  calloc.free(filename_);
  debugEnd?.call('XCASH_Wallet_submitTransaction');
  return s;
}

bool Wallet_submitTransactionUR(wallet ptr, String input) {
  debugStart?.call('XCASH_Wallet_submitTransactionUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final input_ = input.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_submitTransactionUR(ptr, input_);
  calloc.free(input_);
  debugEnd?.call('XCASH_Wallet_submitTransactionUR');
  return s;
}

bool Wallet_hasUnknownKeyImages(wallet ptr) {
  debugStart?.call('XCASH_Wallet_hasUnknownKeyImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_Wallet_hasUnknownKeyImages(ptr);
  debugEnd?.call('XCASH_Wallet_hasUnknownKeyImages');
  return s;
}

bool Wallet_exportKeyImages(wallet ptr, String filename, {required bool all}) {
  debugStart?.call('XCASH_Wallet_exportKeyImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final filename_ = filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_exportKeyImages(ptr, filename_, all);
  calloc.free(filename_);
  debugEnd?.call('XCASH_Wallet_exportKeyImages');
  return s;
}

String Wallet_exportKeyImagesUR(
  wallet ptr, {
  int max_fragment_length = 130,
  bool all = false,
}) {
  debugStart?.call('XCASH_Wallet_exportKeyImagesUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_Wallet_exportKeyImagesUR(ptr, max_fragment_length, all)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_exportKeyImagesUR');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_exportKeyImagesUR', e);
    debugEnd?.call('XCASH_Wallet_exportKeyImagesUR');
    return "";
  }
}

bool Wallet_importKeyImages(wallet ptr, String filename) {
  debugStart?.call('XCASH_Wallet_importKeyImages');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final filename_ = filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_importKeyImages(ptr, filename_);
  calloc.free(filename_);
  debugEnd?.call('XCASH_Wallet_importKeyImages');
  return s;
}

bool Wallet_importKeyImagesUR(wallet ptr, String input) {
  debugStart?.call('XCASH_Wallet_importKeyImagesUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final input_ = input.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_importKeyImagesUR(ptr, input_);
  calloc.free(input_);
  debugEnd?.call('XCASH_Wallet_importKeyImagesUR');
  return s;
}

bool Wallet_exportOutputs(wallet ptr, String filename, {required bool all}) {
  debugStart?.call('XCASH_Wallet_exportOutputs');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final filename_ = filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_exportOutputs(ptr, filename_, all);
  calloc.free(filename_);
  debugEnd?.call('XCASH_Wallet_exportOutputs');
  return s;
}

String Wallet_exportOutputsUR(
  wallet ptr, {
  int max_fragment_length = 130,
  bool all = false,
}) {
  debugStart?.call('XCASH_Wallet_exportOutputsUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_Wallet_exportOutputsUR(ptr, max_fragment_length, all)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_exportOutputsUR');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_exportOutputsUR', e);
    debugEnd?.call('XCASH_Wallet_exportOutputsUR');
    return "";
  }
}

bool Wallet_importOutputs(wallet ptr, String filename) {
  debugStart?.call('XCASH_Wallet_importOutputs');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final filename_ = filename.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_importOutputs(ptr, filename_);
  calloc.free(filename_);
  debugEnd?.call('XCASH_Wallet_importOutputs');
  return s;
}

bool Wallet_importOutputsUR(wallet ptr, String input) {
  debugStart?.call('XCASH_Wallet_importOutputsUR');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final input_ = input.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_importOutputsUR(ptr, input_);
  calloc.free(input_);
  debugEnd?.call('XCASH_Wallet_importOutputsUR');
  return s;
}

bool Wallet_setupBackgroundSync(
  wallet ptr, {
  required int backgroundSyncType,
  required String walletPassword,
  required String backgroundCachePassword,
}) {
  debugStart?.call('XCASH_Wallet_setupBackgroundSync');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final walletPassword_ = walletPassword.toNativeUtf8().cast<Char>();
  final backgroundCachePassword_ =
      backgroundCachePassword.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_Wallet_setupBackgroundSync(
      ptr, backgroundSyncType, walletPassword_, backgroundCachePassword_);
  calloc.free(walletPassword_);
  calloc.free(backgroundCachePassword_);
  debugEnd?.call('XCASH_Wallet_setupBackgroundSync');
  return s;
}

int Wallet_getBackgroundSyncType(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getBackgroundSyncType');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_getBackgroundSyncType(ptr);
  debugEnd?.call('XCASH_Wallet_getBackgroundSyncType');
  return v;
}

bool Wallet_startBackgroundSync(wallet ptr) {
  debugStart?.call('XCASH_Wallet_startBackgroundSync');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_startBackgroundSync(ptr);
  debugEnd?.call('XCASH_Wallet_startBackgroundSync');
  return v;
}

bool Wallet_stopBackgroundSync(wallet ptr, String walletPassword) {
  debugStart?.call('XCASH_Wallet_stopBackgroundSync');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final walletPassword_ = walletPassword.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_Wallet_stopBackgroundSync(ptr, walletPassword_);
  calloc.free(walletPassword_);
  debugEnd?.call('XCASH_Wallet_stopBackgroundSync');
  return v;
}

bool Wallet_isBackgroundSyncing(wallet ptr) {
  debugStart?.call('XCASH_Wallet_isBackgroundSyncing');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_isBackgroundSyncing(ptr);
  debugEnd?.call('XCASH_Wallet_isBackgroundSyncing');
  return v;
}

bool Wallet_isBackgroundWallet(wallet ptr) {
  debugStart?.call('XCASH_Wallet_isBackgroundWallet');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_isBackgroundWallet(ptr);
  debugEnd?.call('XCASH_Wallet_isBackgroundWallet');
  return v;
}

TransactionHistory Wallet_history(wallet ptr) {
  debugStart?.call('XCASH_Wallet_history');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final history = lib!.XCASH_Wallet_history(ptr);
  debugEnd?.call('XCASH_Wallet_history');
  return history;
}

AddressBook Wallet_addressBook(wallet ptr) {
  debugStart?.call('XCASH_Wallet_addressBook');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final history = lib!.XCASH_Wallet_addressBook(ptr);
  debugEnd?.call('XCASH_Wallet_addressBook');
  return history;
}

AddressBook Wallet_coins(wallet ptr) {
  debugStart?.call('XCASH_Wallet_coins');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final history = lib!.XCASH_Wallet_coins(ptr);
  debugEnd?.call('XCASH_Wallet_coins');
  return history;
}

AddressBook Wallet_subaddress(wallet ptr) {
  debugStart?.call('XCASH_Wallet_subaddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final history = lib!.XCASH_Wallet_subaddress(ptr);
  debugEnd?.call('XCASH_Wallet_subaddress');
  return history;
}

AddressBook Wallet_subaddressAccount(wallet ptr) {
  debugStart?.call('XCASH_Wallet_subaddressAccount');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final history = lib!.XCASH_Wallet_subaddressAccount(ptr);
  debugEnd?.call('XCASH_Wallet_subaddressAccount');
  return history;
}

int Wallet_defaultMixin(wallet ptr) {
  debugStart?.call('XCASH_Wallet_defaultMixin');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_defaultMixin(ptr);
  debugEnd?.call('XCASH_Wallet_defaultMixin');
  return v;
}

void Wallet_setDefaultMixin(wallet ptr, int arg) {
  debugStart?.call('XCASH_Wallet_setDefaultMixin');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_setDefaultMixin(ptr, arg);
  debugEnd?.call('XCASH_Wallet_setDefaultMixin');
  return v;
}

bool Wallet_setCacheAttribute(wallet ptr,
    {required String key, required String value}) {
  debugStart?.call('XCASH_Wallet_setCacheAttribute');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final key_ = key.toNativeUtf8().cast<Char>();
  final value_ = value.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_Wallet_setCacheAttribute(ptr, key_, value_);
  calloc.free(key_);
  calloc.free(value_);
  debugEnd?.call('XCASH_Wallet_setCacheAttribute');
  return v;
}

String Wallet_getCacheAttribute(wallet ptr, {required String key}) {
  debugStart?.call('XCASH_Wallet_getCacheAttribute');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final key_ = key.toNativeUtf8().cast<Char>();
    final strPtr = lib!.XCASH_Wallet_getCacheAttribute(ptr, key_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(key_);
    debugEnd?.call('XCASH_Wallet_getCacheAttribute');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getCacheAttribute', e);
    debugEnd?.call('XCASH_Wallet_getCacheAttribute');
    return "";
  }
}

bool Wallet_setUserNote(wallet ptr,
    {required String txid, required String note}) {
  debugStart?.call('XCASH_Wallet_setUserNote');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final txid_ = txid.toNativeUtf8().cast<Char>();
  final note_ = note.toNativeUtf8().cast<Char>();
  final v = lib!.XCASH_Wallet_setUserNote(ptr, txid_, note_);
  calloc.free(txid_);
  calloc.free(note_);
  debugEnd?.call('XCASH_Wallet_setUserNote');
  return v;
}

String Wallet_getUserNote(wallet ptr, {required String txid}) {
  debugStart?.call('XCASH_Wallet_getUserNote');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final txid_ = txid.toNativeUtf8().cast<Char>();
    final strPtr = lib!.XCASH_Wallet_getUserNote(ptr, txid_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(txid_);
    debugEnd?.call('XCASH_Wallet_getUserNote');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getUserNote', e);
    debugEnd?.call('XCASH_Wallet_getUserNote');
    return "";
  }
}

String Wallet_getTxKey(wallet ptr, {required String txid}) {
  debugStart?.call('XCASH_Wallet_getTxKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final txid_ = txid.toNativeUtf8().cast<Char>();
    final strPtr = lib!.XCASH_Wallet_getTxKey(ptr, txid_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(txid_);
    debugEnd?.call('XCASH_Wallet_getTxKey');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_getTxKey', e);
    debugEnd?.call('XCASH_Wallet_getTxKey');
    return "";
  }
}

String Wallet_signMessage(
  wallet ptr, {
  required String message,
  required String address,
}) {
  debugStart?.call('XCASH_Wallet_signMessage');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final message_ = message.toNativeUtf8().cast<Char>();
    final address_ = address.toNativeUtf8().cast<Char>();
    final strPtr =
        lib!.XCASH_Wallet_signMessage(ptr, message_, address_).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    calloc.free(message_);
    calloc.free(address_);
    debugEnd?.call('XCASH_Wallet_signMessage');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_signMessage', e);
    debugEnd?.call('XCASH_Wallet_signMessage');
    return "";
  }
}

bool Wallet_verifySignedMessage(
  wallet ptr, {
  required String message,
  required String address,
  required String signature,
}) {
  debugStart?.call('XCASH_Wallet_verifySignedMessage');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final message_ = message.toNativeUtf8().cast<Char>();
  final address_ = address.toNativeUtf8().cast<Char>();
  final signature_ = signature.toNativeUtf8().cast<Char>();
  final v = lib!
      .XCASH_Wallet_verifySignedMessage(ptr, message_, address_, signature_);
  calloc.free(message_);
  calloc.free(address_);
  calloc.free(signature_);
  debugEnd?.call('XCASH_Wallet_verifySignedMessage');
  return v;
}

bool Wallet_rescanSpent(wallet ptr) {
  debugStart?.call('XCASH_Wallet_rescanSpent');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_rescanSpent(ptr);
  debugEnd?.call('XCASH_Wallet_rescanSpent');
  return v;
}

void Wallet_setOffline(wallet ptr, {required bool offline}) {
  debugStart?.call('XCASH_Wallet_setOffline');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final setOffline = lib!.XCASH_Wallet_setOffline(ptr, offline);
  debugEnd?.call('XCASH_Wallet_setOffline');
  return setOffline;
}

bool Wallet_isOffline(wallet ptr) {
  debugStart?.call('XCASH_Wallet_isOffline');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final isOffline = lib!.XCASH_Wallet_isOffline(ptr);
  debugEnd?.call('XCASH_Wallet_isOffline');
  return isOffline;
}

void Wallet_segregatePreForkOutputs(wallet ptr, {required bool segregate}) {
  debugStart?.call('XCASH_Wallet_segregatePreForkOutputs');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_segregatePreForkOutputs(ptr, segregate);
  debugEnd?.call('XCASH_Wallet_segregatePreForkOutputs');
  return v;
}

void Wallet_segregationHeight(wallet ptr, {required int height}) {
  debugStart?.call('XCASH_Wallet_segregationHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_segregationHeight(ptr, height);
  debugEnd?.call('XCASH_Wallet_segregationHeight');
  return v;
}

void Wallet_keyReuseMitigation2(wallet ptr, {required bool mitigation}) {
  debugStart?.call('XCASH_Wallet_keyReuseMitigation2');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_keyReuseMitigation2(ptr, mitigation);
  debugEnd?.call('XCASH_Wallet_keyReuseMitigation2');
  return v;
}

bool Wallet_lockKeysFile(wallet ptr) {
  debugStart?.call('XCASH_Wallet_lockKeysFile');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_lockKeysFile(ptr);
  debugEnd?.call('XCASH_Wallet_lockKeysFile');
  return v;
}

bool Wallet_unlockKeysFile(wallet ptr) {
  debugStart?.call('XCASH_Wallet_unlockKeysFile');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_unlockKeysFile(ptr);
  debugEnd?.call('XCASH_Wallet_unlockKeysFile');
  return v;
}

bool Wallet_isKeysFileLocked(wallet ptr) {
  debugStart?.call('XCASH_Wallet_isKeysFileLocked');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_isKeysFileLocked(ptr);
  debugEnd?.call('XCASH_Wallet_isKeysFileLocked');
  return v;
}

int Wallet_getDeviceType(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getDeviceType');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_getDeviceType(ptr);
  debugEnd?.call('XCASH_Wallet_getDeviceType');
  return v;
}

int Wallet_coldKeyImageSync(wallet ptr,
    {required int spent, required int unspent}) {
  debugStart?.call('XCASH_Wallet_coldKeyImageSync');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final v = lib!.XCASH_Wallet_coldKeyImageSync(ptr, spent, unspent);
  debugEnd?.call('XCASH_Wallet_coldKeyImageSync');
  return v;
}

String Wallet_deviceShowAddress(wallet ptr,
    {required int accountIndex, required int addressIndex}) {
  debugStart?.call('XCASH_Wallet_deviceShowAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!
        .XCASH_Wallet_deviceShowAddress(ptr, accountIndex, addressIndex)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_Wallet_deviceShowAddress');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_Wallet_deviceShowAddress', e);
    debugEnd?.call('XCASH_Wallet_deviceShowAddress');
    return "";
  }
}

bool Wallet_reconnectDevice(wallet ptr) {
  debugStart?.call('XCASH_Wallet_reconnectDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_reconnectDevice(ptr);
  debugEnd?.call('XCASH_Wallet_reconnectDevice');
  return ret;
}

int Wallet_getBytesReceived(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getBytesReceived');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final getBytesReceived = lib!.XCASH_Wallet_getBytesReceived(ptr);
  debugEnd?.call('XCASH_Wallet_getBytesReceived');
  return getBytesReceived;
}

int XCASH_Wallet_getBytesSent(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getBytesSent');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final getBytesSent = lib!.XCASH_Wallet_getBytesSent(ptr);
  debugEnd?.call('XCASH_Wallet_getBytesSent');
  return getBytesSent;
}

bool Wallet_getStateIsConnected(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getStateIsConnected');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getStateIsConnected(ptr);
  debugEnd?.call('XCASH_Wallet_getStateIsConnected');
  return ret;
}

Pointer<UnsignedChar> Wallet_getSendToDevice(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getSendToDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getSendToDevice(ptr);
  debugEnd?.call('XCASH_Wallet_getSendToDevice');
  return ret;
}

int Wallet_getSendToDeviceLength(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getSendToDeviceLength');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getSendToDeviceLength(ptr);
  debugEnd?.call('XCASH_Wallet_getSendToDeviceLength');
  return ret;
}

Pointer<UnsignedChar> Wallet_getReceivedFromDevice(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getReceivedFromDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getReceivedFromDevice(ptr);
  debugEnd?.call('XCASH_Wallet_getReceivedFromDevice');
  return ret;
}

int Wallet_getReceivedFromDeviceLength(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getReceivedFromDeviceLength');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getReceivedFromDeviceLength(ptr);
  debugEnd?.call('XCASH_Wallet_getReceivedFromDeviceLength');
  return ret;
}

bool Wallet_getWaitsForDeviceSend(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getWaitsForDeviceSend');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getWaitsForDeviceSend(ptr);
  debugEnd?.call('XCASH_Wallet_getWaitsForDeviceSend');
  return ret;
}

bool Wallet_getWaitsForDeviceReceive(wallet ptr) {
  debugStart?.call('XCASH_Wallet_getWaitsForDeviceReceive');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_getWaitsForDeviceReceive(ptr);
  debugEnd?.call('XCASH_Wallet_getWaitsForDeviceReceive');
  return ret;
}

void Wallet_setDeviceReceivedData(
    wallet ptr, Pointer<UnsignedChar> data, int len) {
  debugStart?.call('XCASH_Wallet_setDeviceReceivedData');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_setDeviceReceivedData(ptr, data, len);
  debugEnd?.call('XCASH_Wallet_setDeviceReceivedData');
  return ret;
}

void Wallet_setDeviceSendData(wallet ptr, Pointer<UnsignedChar> data, int len) {
  debugStart?.call('XCASH_Wallet_setDeviceSendData');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final ret = lib!.XCASH_Wallet_setDeviceSendData(ptr, data, len);
  debugEnd?.call('XCASH_Wallet_setDeviceSendData');
  return ret;
}

// WalletManager

typedef WalletManager = Pointer<Void>;

wallet WalletManager_createWallet(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  String language = "English",
  int networkType = 0,
}) {
  debugStart?.call('XCASH_WalletManager_createWallet');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final language_ = language.toNativeUtf8().cast<Char>();
  final w = lib!.XCASH_WalletManager_createWallet(
      wm_ptr, path_, password_, language_, networkType);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(language_);
  debugEnd?.call('XCASH_WalletManager_createWallet');
  return w;
}

wallet WalletManager_openWallet(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  int networkType = 0,
}) {
  debugStart?.call('XCASH_WalletManager_openWallet');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final w = lib!
      .XCASH_WalletManager_openWallet(wm_ptr, path_, password_, networkType);
  calloc.free(path_);
  calloc.free(password_);
  debugEnd?.call('XCASH_WalletManager_openWallet');
  return w;
}

wallet WalletManager_recoveryWallet(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  required String mnemonic,
  int networkType = 0,
  required int restoreHeight,
  int kdfRounds = 0,
  required String seedOffset,
}) {
  debugStart?.call('XCASH_WalletManager_recoveryWallet');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final mnemonic_ = mnemonic.toNativeUtf8().cast<Char>();
  final seedOffset_ = seedOffset.toNativeUtf8().cast<Char>();
  final w = lib!.XCASH_WalletManager_recoveryWallet(wm_ptr, path_, password_,
      mnemonic_, networkType, restoreHeight, kdfRounds, seedOffset_);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(mnemonic_);
  calloc.free(seedOffset_);
  debugEnd?.call('XCASH_WalletManager_recoveryWallet');
  return w;
}

wallet WalletManager_createWalletFromKeys(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  String language = "English",
  int nettype = 1,
  required int restoreHeight,
  required String addressString,
  required String viewKeyString,
  required String spendKeyString,
  int kdf_rounds = 1,
}) {
  lib ??= XcashC(DynamicLibrary.open(libPath));
  debugStart?.call('XCASH_WalletManager_createWalletFromKeys');

  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final language_ = language.toNativeUtf8().cast<Char>();
  final addressString_ = addressString.toNativeUtf8().cast<Char>();
  final viewKeyString_ = viewKeyString.toNativeUtf8().cast<Char>();
  final spendKeyString_ = spendKeyString.toNativeUtf8().cast<Char>();

  final w = lib!.XCASH_WalletManager_createWalletFromKeys(
    wm_ptr,
    path_,
    password_,
    language_,
    nettype,
    restoreHeight,
    addressString_,
    viewKeyString_,
    spendKeyString_,
    kdf_rounds,
  );
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(language_);
  calloc.free(addressString_);
  calloc.free(viewKeyString_);
  calloc.free(spendKeyString_);
  debugEnd?.call('XCASH_WalletManager_createWalletFromKeys');
  return w;
}

wallet WalletManager_createDeterministicWalletFromSpendKey(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  int networkType = 0,
  required String language,
  required String spendKeyString,
  required bool newWallet,
  required int restoreHeight,
  int kdfRounds = 1,
}) {
  debugStart
      ?.call('XCASH_WalletManager_createDeterministicWalletFromSpendKey');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final language_ = language.toNativeUtf8().cast<Char>();
  final spendKeyString_ = spendKeyString.toNativeUtf8().cast<Char>();
  final w = lib!.XCASH_WalletManager_createDeterministicWalletFromSpendKey(
      wm_ptr,
      path_,
      password_,
      language_,
      networkType,
      restoreHeight,
      spendKeyString_,
      kdfRounds);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(language_);
  calloc.free(spendKeyString_);
  debugEnd?.call('XCASH_WalletManager_createDeterministicWalletFromSpendKey');
  return w;
}

wallet WalletManager_createWalletFromDevice(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  int networkType = 0,
  required String deviceName,
  int restoreHeight = 0,
  String subaddressLookahead = "",
  int kdfRounds = 1,
}) {
  debugStart?.call('XCASH_WalletManager_createWalletFromDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final deviceName_ = deviceName.toNativeUtf8().cast<Char>();
  final subaddressLookahead_ = subaddressLookahead.toNativeUtf8().cast<Char>();
  final w = lib!.XCASH_WalletManager_createWalletFromDevice(
      wm_ptr,
      path_,
      password_,
      networkType,
      deviceName_,
      restoreHeight,
      subaddressLookahead_,
      defaultSeparator, // ignore
      defaultSeparator, // ignore
      kdfRounds);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(deviceName_);
  calloc.free(subaddressLookahead_);
  debugEnd?.call('XCASH_WalletManager_createWalletFromDevice');
  return w;
}

wallet WalletManager_createWalletFromPolyseed(
  WalletManager wm_ptr, {
  required String path,
  required String password,
  int networkType = 0,
  required String mnemonic,
  required String seedOffset,
  required bool newWallet,
  required int restoreHeight,
  required int kdfRounds,
}) {
  debugStart?.call('XCASH_WalletManager_createWalletFromPolyseed');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final mnemonic_ = mnemonic.toNativeUtf8().cast<Char>();
  final seedOffset_ = seedOffset.toNativeUtf8().cast<Char>();
  final w = lib!.XCASH_WalletManager_createWalletFromPolyseed(
      wm_ptr,
      path_,
      password_,
      networkType,
      mnemonic_,
      seedOffset_,
      newWallet,
      restoreHeight,
      kdfRounds);
  calloc.free(path_);
  calloc.free(password_);
  calloc.free(mnemonic_);
  calloc.free(seedOffset_);
  debugEnd?.call('XCASH_WalletManager_createWalletFromPolyseed');
  return w;
}

bool WalletManager_closeWallet(WalletManager wm_ptr, wallet ptr, bool store) {
  debugStart?.call('XCASH_WalletManager_closeWallet');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final closeWallet = lib!.XCASH_WalletManager_closeWallet(wm_ptr, ptr, store);
  debugEnd?.call('XCASH_WalletManager_closeWallet');
  return closeWallet;
}

bool WalletManager_walletExists(WalletManager wm_ptr, String path) {
  debugStart?.call('XCASH_WalletManager_walletExists');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final path_ = path.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_walletExists(wm_ptr, path_);
  calloc.free(path_);
  debugEnd?.call('XCASH_WalletManager_walletExists');
  return s;
}

bool WalletManager_verifyWalletPassword(
  WalletManager wm_ptr, {
  required String keysFileName,
  required String password,
  required bool noSpendKey,
  required int kdfRounds,
}) {
  debugStart?.call('XCASH_WalletManager_verifyWalletPassword');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final keysFileName_ = keysFileName.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_verifyWalletPassword(
      wm_ptr, keysFileName_, password_, noSpendKey, kdfRounds);
  calloc.free(keysFileName_);
  calloc.free(password_);
  debugEnd?.call('XCASH_WalletManager_verifyWalletPassword');
  return s;
}

int WalletManager_queryWalletDevice(
    WalletManager wm_ptr, {
      required String keysFileName,
      required String password,
      required int kdfRounds,
    }) {
  debugStart?.call('XCASH_WalletManager_queryWalletDevice');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final keysFileName_ = keysFileName.toNativeUtf8().cast<Char>();
  final password_ = password.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_queryWalletDevice(
      wm_ptr, keysFileName_, password_, kdfRounds);
  calloc.free(keysFileName_);
  calloc.free(password_);
  debugEnd?.call('XCASH_WalletManager_queryWalletDevice');
  return s;
}

List<String> WalletManager_findWallets(WalletManager wm_ptr,
    {required String path}) {
  debugStart?.call('XCASH_WalletManager_findWallets');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final path_ = path.toNativeUtf8().cast<Char>();
    final strPtr = lib!
        .XCASH_WalletManager_findWallets(wm_ptr, path_, defaultSeparator)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    calloc.free(path_);
    if (str.isNotEmpty) {
      XCASH_free(strPtr.cast());
    }
    debugEnd?.call('XCASH_WalletManager_findWallets');
    return str.split(";");
  } catch (e) {
    errorHandler?.call('XCASH_WalletManager_findWallets', e);
    debugEnd?.call('XCASH_WalletManager_findWallets');
    return [];
  }
}

String WalletManager_errorString(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_errorString');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final strPtr = lib!.XCASH_WalletManager_errorString(wm_ptr).cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_WalletManager_errorString');
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_WalletManager_errorString', e);
    debugEnd?.call('XCASH_WalletManager_errorString');
    return "";
  }
}

void WalletManager_setDaemonAddress(WalletManager wm_ptr, String address) {
  debugStart?.call('XCASH_WalletManager_setDaemonAddress');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_setDaemonAddress(wm_ptr, address_);
  calloc.free(address_);
  debugEnd?.call('XCASH_WalletManager_setDaemonAddress');
  return s;
}

int WalletManager_blockchainHeight(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_blockchainHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_blockchainHeight(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_blockchainHeight');
  return s;
}

int WalletManager_blockchainTargetHeight(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_blockchainTargetHeight');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_blockchainTargetHeight(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_blockchainTargetHeight');
  return s;
}

int WalletManager_networkDifficulty(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_networkDifficulty');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_networkDifficulty(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_networkDifficulty');
  return s;
}

double WalletManager_miningHashRate(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_miningHashRate');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_miningHashRate(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_miningHashRate');
  return s;
}

int WalletManager_blockTarget(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_blockTarget');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_blockTarget(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_blockTarget');
  return s;
}

bool WalletManager_isMining(WalletManager wm_ptr) {
  debugStart?.call('XCASH_WalletManager_isMining');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManager_isMining(wm_ptr);
  debugEnd?.call('XCASH_WalletManager_isMining');
  return s;
}

bool WalletManager_startMining(
  WalletManager wm_ptr, {
  required String address,
  required int threads,
  required bool backgroundMining,
  required bool ignoreBattery,
}) {
  debugStart?.call('XCASH_WalletManager_startMining');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_startMining(
      wm_ptr, address_, threads, backgroundMining, ignoreBattery);
  calloc.free(address_);
  debugEnd?.call('XCASH_WalletManager_startMining');
  return s;
}

bool WalletManager_stopMining(WalletManager wm_ptr, String address) {
  debugStart?.call('XCASH_WalletManager_stopMining');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_stopMining(wm_ptr, address_);
  calloc.free(address_);
  debugEnd?.call('XCASH_WalletManager_stopMining');
  return s;
}

String WalletManager_resolveOpenAlias(
  WalletManager wm_ptr, {
  required String address,
  required bool dnssecValid,
}) {
  debugStart?.call('XCASH_WalletManager_resolveOpenAlias');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  try {
    final address_ = address.toNativeUtf8().cast<Char>();
    final strPtr = lib!
        .XCASH_WalletManager_resolveOpenAlias(wm_ptr, address_, dnssecValid)
        .cast<Utf8>();
    final str = strPtr.toDartString();
    XCASH_free(strPtr.cast());
    debugEnd?.call('XCASH_WalletManager_resolveOpenAlias');
    calloc.free(address_);
    return str;
  } catch (e) {
    errorHandler?.call('XCASH_WalletManager_resolveOpenAlias', e);
    debugEnd?.call('XCASH_WalletManager_resolveOpenAlias');
    return "";
  }
}

bool WalletManager_setProxy(WalletManager wm_ptr, String address) {
  debugStart?.call('XCASH_WalletManager_setProxy');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final address_ = address.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManager_setProxy(wm_ptr, address_);
  calloc.free(address_);
  debugEnd?.call('XCASH_WalletManager_setProxy');
  return s;
}

void WalletManagerFactory_setLogLevel(int level) {
  debugStart?.call('XCASH_WalletManagerFactory_setLogLevel');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManagerFactory_setLogLevel(level);
  debugEnd?.call('XCASH_WalletManagerFactory_setLogLevel');
  return s;
}

void WalletManagerFactory_setLogCategories(String categories) {
  debugStart?.call('XCASH_WalletManagerFactory_setLogCategories');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final categories_ = categories.toNativeUtf8().cast<Char>();
  final s = lib!.XCASH_WalletManagerFactory_setLogCategories(categories_);
  calloc.free(categories_);
  debugEnd?.call('XCASH_WalletManagerFactory_setLogCategories');
  return s;
}

WalletManager WalletManagerFactory_getWalletManager() {
  debugStart?.call('XCASH_WalletManagerFactory_getWalletManager');
  lib ??= XcashC(DynamicLibrary.open(libPath));
  final s = lib!.XCASH_WalletManagerFactory_getWalletManager();
  debugEnd?.call('XCASH_WalletManagerFactory_getWalletManager');
  return s;
}

// class LogLevel {
//   int get LogLevel_Silent => lib!.LogLevel_Silent;
//   int get LogLevel_0 => lib!.LogLevel_0;
//   int get LogLevel_1 => lib!.LogLevel_1;
//   int get LogLevel_2 => lib!.LogLevel_2;
//   int get LogLevel_3 => lib!.LogLevel_3;
//   int get LogLevel_4 => lib!.LogLevel_4;
//   int get LogLevel_Min => LogLevel_Silent;
//   int get LogLevel_Max => lib!.LogLevel_4;
// }

// class ConnectionStatus {
//   int get Disconnected => lib!.WalletConnectionStatus_Disconnected;
//   int get Connected => lib!.WalletConnectionStatus_Connected;
//   int get WrongVersion => lib!.WalletConnectionStatus_WrongVersion;
// }

// DEBUG

class libOk {
  libOk(
    this.test1,
    this.test2,
    this.test3,
    this.test4,
    this.test5,
    this.test5_std,
  );
  final bool test1;
  final int test2;
  final int test3;
  final Pointer<Void> test4;
  final Pointer<Char> test5;
  String get test5_str {
    try {
      return test5.cast<Utf8>().toDartString();
    } catch (e) {
      return "$e";
    }
  }

  String get test5_str16 {
    try {
      return test5.cast<Utf16>().toDartString();
    } catch (e) {
      return "$e";
    }
  }

  final Pointer<Char> test5_std;
  String get test5_std_str {
    try {
      return test5_std.cast<Utf8>().toDartString();
    } catch (e) {
      return "$e";
    }
  }

  String get test5_std_str16 {
    try {
      return test5_std.cast<Utf16>().toDartString();
    } catch (e) {
      return "$e";
    }
  }

  Map<String, dynamic> toJson() {
    return {
      "test1": test1,
      "test2": test2,
      "test3": test3,
      "test4": test4.toString(),
      "test5": test5.toString(),
      "test5_str": test5_str,
      "test5_std": test5_std.toString(),
      "test5_std_str": test5_std_str,
    };
  }
}

libOk isLibOk() {
  lib ??= XcashC(DynamicLibrary.open(libPath));
  lib!.XCASH_DEBUG_test0();
  final test1 = lib!.XCASH_DEBUG_test1(true);
  final test2 = lib!.XCASH_DEBUG_test2(-1);
  final test3 = lib!.XCASH_DEBUG_test3(1);
  final test4 = lib!.XCASH_DEBUG_test4(1);
  final test5 = lib!.XCASH_DEBUG_test5();
  final test5_std = lib!.XCASH_DEBUG_test5_std();
  return libOk(test1, test2, test3, test4, test5, test5_std);
}

// cake world

typedef WalletListener = Pointer<Void>;

WalletListener XCASH_cw_getWalletListener(wallet wptr) {
  debugStart?.call('XCASH_cw_getWalletListener');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_getWalletListener(wptr);
  debugEnd?.call('XCASH_cw_getWalletListener');
  return s;
}

void XCASH_cw_WalletListener_resetNeedToRefresh(WalletListener wlptr) {
  debugStart?.call('XCASH_cw_WalletListener_resetNeedToRefresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_WalletListener_resetNeedToRefresh(wlptr);
  debugEnd?.call('XCASH_cw_WalletListener_resetNeedToRefresh');
  return s;
}

bool XCASH_cw_WalletListener_isNeedToRefresh(WalletListener wlptr) {
  debugStart?.call('XCASH_cw_WalletListener_isNeedToRefresh');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_WalletListener_isNeedToRefresh(wlptr);
  debugEnd?.call('XCASH_cw_WalletListener_isNeedToRefresh');
  return s;
}

bool XCASH_cw_WalletListener_isNewTransactionExist(WalletListener wlptr) {
  debugStart?.call('XCASH_cw_WalletListener_isNewTransactionExist');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_WalletListener_isNewTransactionExist(wlptr);
  debugEnd?.call('XCASH_cw_WalletListener_isNewTransactionExist');
  return s;
}

void XCASH_cw_WalletListener_resetIsNewTransactionExist(WalletListener wlptr) {
  debugStart?.call('XCASH_cw_WalletListener_resetIsNewTransactionExist');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_WalletListener_resetIsNewTransactionExist(wlptr);
  debugEnd?.call('XCASH_cw_WalletListener_resetIsNewTransactionExist');
  return s;
}

int XCASH_cw_WalletListener_height(WalletListener wlptr) {
  debugStart?.call('XCASH_cw_WalletListener_height');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_cw_WalletListener_height(wlptr);
  debugEnd?.call('XCASH_cw_WalletListener_height');
  return s;
}

String XCASH_checksum_wallet2_api_c_h() {
  debugStart?.call('XCASH_checksum_wallet2_api_c_h');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_checksum_wallet2_api_c_h();
  debugEnd?.call('XCASH_checksum_wallet2_api_c_h');
  return s.cast<Utf8>().toDartString();
}

String XCASH_checksum_wallet2_api_c_cpp() {
  debugStart?.call('XCASH_checksum_wallet2_api_c_cpp');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_checksum_wallet2_api_c_cpp();
  debugEnd?.call('XCASH_checksum_wallet2_api_c_cpp');
  return s.cast<Utf8>().toDartString();
}

String XCASH_checksum_wallet2_api_c_exp() {
  debugStart?.call('XCASH_checksum_wallet2_api_c_exp');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_checksum_wallet2_api_c_exp();
  debugEnd?.call('XCASH_checksum_wallet2_api_c_exp');
  return s.cast<Utf8>().toDartString();
}

void XCASH_free(Pointer<Void> wlptr) {
  debugStart?.call('XCASH_free');
  lib ??= XcashC(DynamicLibrary.open(libPath));

  final s = lib!.XCASH_free(wlptr);
  debugEnd?.call('XCASH_free');
  return s;
}
