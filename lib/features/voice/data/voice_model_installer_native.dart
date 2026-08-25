import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/voice_language.dart';
import '../domain/voice_model.dart';
import 'voice_model_installer.dart';

VoiceModelInstaller createVoiceModelInstaller() => NativeVoiceModelInstaller();

abstract interface class VoiceModelTransport {
  Future<Stream<List<int>>> open(Uri uri);

  Future<void> close();
}

class NativeVoiceModelInstaller implements VoiceModelInstaller {
  NativeVoiceModelInstaller({VoiceModelTransport? transport, Directory? root})
    : this._(transport ?? _HttpVoiceModelTransport(), root);

  NativeVoiceModelInstaller._(this._transport, this._root);

  final VoiceModelTransport _transport;
  final Directory? _root;

  @override
  Future<VoiceModel?> installedModel(VoiceLanguage language) async {
    final manifest = _manifest(language);
    final directory = await _modelDirectory(language);
    if (!await _hasExpectedFiles(directory, manifest, verifyHashes: false)) {
      return null;
    }
    return _model(directory, manifest);
  }

  @override
  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) async {
    final manifest = _manifest(language);
    final destination = await _modelDirectory(language);
    if (await _hasExpectedFiles(destination, manifest, verifyHashes: true)) {
      onProgress(1);
      return _model(destination, manifest);
    }

    final root = destination.parent;
    await root.create(recursive: true);
    final staging = Directory(
      '${root.path}${Platform.pathSeparator}.${language.code}-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create();
    var completedBytes = 0;
    try {
      for (final file in manifest.files) {
        final output = File(
          '${staging.path}${Platform.pathSeparator}${file.localName}',
        );
        final response = await _transport.open(file.uri);
        final sink = output.openWrite();
        var fileBytes = 0;
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            fileBytes += chunk.length;
            onProgress((completedBytes + fileBytes) / manifest.totalBytes);
          }
        } finally {
          await sink.close();
        }
        if (fileBytes != file.size) {
          throw const VoiceModelSizeException();
        }
        final digest = await sha256.bind(output.openRead()).first;
        if (digest.toString() != file.sha256) {
          throw const VoiceModelChecksumException();
        }
        completedBytes += fileBytes;
      }

      Directory? backup;
      if (await destination.exists()) {
        backup = await destination.rename(
          '${destination.path}.backup-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      try {
        await staging.rename(destination.path);
        await backup?.delete(recursive: true);
      } on Object {
        if (backup != null && await backup.exists()) {
          await backup.rename(destination.path);
        }
        rethrow;
      }
      onProgress(1);
      return _model(destination, manifest);
    } on VoiceModelInstallException {
      rethrow;
    } on FileSystemException {
      throw const VoiceModelStorageException();
    } on SocketException {
      throw const VoiceModelNetworkException();
    } on Object {
      throw const VoiceModelInstallExceptionUnexpected();
    } finally {
      try {
        await _transport.close();
      } on Object {
        // Closing the transport must not prevent staging cleanup.
      } finally {
        try {
          if (await staging.exists()) await staging.delete(recursive: true);
        } on Object {
          // The installation result is already determined; never mask it with
          // cleanup noise. The staging directory remains private and is
          // retried by the next installation attempt.
        }
      }
    }
  }

  @override
  Future<void> remove(VoiceLanguage language) async {
    final directory = await _modelDirectory(language);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<Directory> _modelDirectory(VoiceLanguage language) async {
    final support = _root ?? await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}voice_models'
      '${Platform.pathSeparator}${language.code}',
    );
  }

  Future<bool> _hasExpectedFiles(
    Directory directory,
    _ModelManifest manifest, {
    required bool verifyHashes,
  }) async {
    if (!await directory.exists()) return false;
    for (final expected in manifest.files) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}${expected.localName}',
      );
      if (!await file.exists() || await file.length() != expected.size) {
        return false;
      }
      if (verifyHashes) {
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != expected.sha256) return false;
      }
    }
    return true;
  }

  VoiceModel _model(Directory directory, _ModelManifest manifest) => VoiceModel(
    language: manifest.language,
    encoderPath: '${directory.path}${Platform.pathSeparator}encoder.int8.onnx',
    decoderPath: '${directory.path}${Platform.pathSeparator}decoder.onnx',
    joinerPath: '${directory.path}${Platform.pathSeparator}joiner.int8.onnx',
    tokensPath: '${directory.path}${Platform.pathSeparator}tokens.txt',
    modelType: manifest.modelType,
  );
}

final class _HttpVoiceModelTransport implements VoiceModelTransport {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  @override
  Future<Stream<List<int>>> open(Uri uri) async {
    try {
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const VoiceModelHttpException();
      }
      return response;
    } on VoiceModelInstallException {
      rethrow;
    } on Object {
      throw const VoiceModelNetworkException();
    }
  }

  @override
  Future<void> close() async => _client.close(force: true);
}

_ModelManifest _manifest(VoiceLanguage language) => switch (language) {
  VoiceLanguage.french => _frenchManifest,
  VoiceLanguage.english => _englishManifest,
};

const _frenchBase =
    'https://huggingface.co/shaojieli/'
    'sherpa-onnx-streaming-zipformer-fr-2023-04-14/resolve/'
    '3db9565d9633758d6b87b9a7b3dc09ebfb6b2c73';
const _englishBase =
    'https://huggingface.co/csukuangfj/'
    'sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/'
    '672fbf1b30579d6585301139bb363f42a0ad4a24';

final _frenchManifest = _ModelManifest(
  language: VoiceLanguage.french,
  modelType: 'zipformer',
  files: [
    _ModelFile(
      localName: 'encoder.int8.onnx',
      uri: Uri.parse(
        '$_frenchBase/encoder-epoch-29-avg-9-with-averaged-model.int8.onnx',
      ),
      size: 126655903,
      sha256:
          '47a94a7fdc8dff63d708be4ea0535747640224467f91e238311f1ddbdd09327e',
    ),
    _ModelFile(
      localName: 'decoder.onnx',
      uri: Uri.parse(
        '$_frenchBase/decoder-epoch-29-avg-9-with-averaged-model.onnx',
      ),
      size: 2092272,
      sha256:
          '3ef2840b684440e26382af87b2174d25732a9f113f1965cd8abba7ffc5d033fb',
    ),
    _ModelFile(
      localName: 'joiner.int8.onnx',
      uri: Uri.parse(
        '$_frenchBase/joiner-epoch-29-avg-9-with-averaged-model.int8.onnx',
      ),
      size: 259572,
      sha256:
          'fc2f3bb851a15a532c6f2422d53eecd1ca949f12b0897e07a852021c30481711',
    ),
    _ModelFile(
      localName: 'tokens.txt',
      uri: Uri.parse('$_frenchBase/tokens.txt'),
      size: 4819,
      sha256:
          '37fb3f2a7bcb85e5fff3f1f66be04e6fbb05077a22f56d177fe85704e945fb31',
    ),
  ],
);

final _englishManifest = _ModelManifest(
  language: VoiceLanguage.english,
  modelType: 'zipformer2',
  files: [
    _ModelFile(
      localName: 'encoder.int8.onnx',
      uri: Uri.parse(
        '$_englishBase/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
      ),
      size: 71083163,
      sha256:
          '563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1',
    ),
    _ModelFile(
      localName: 'decoder.onnx',
      uri: Uri.parse(
        '$_englishBase/decoder-epoch-99-avg-1-chunk-16-left-128.onnx',
      ),
      size: 2092621,
      sha256:
          '7bf787f90b194b307e5a4ad6a34fadb4e748304c35f78a8d66358a05b13ee6ef',
    ),
    _ModelFile(
      localName: 'joiner.int8.onnx',
      uri: Uri.parse(
        '$_englishBase/joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
      ),
      size: 259335,
      sha256:
          'd944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297',
    ),
    _ModelFile(
      localName: 'tokens.txt',
      uri: Uri.parse('$_englishBase/tokens.txt'),
      size: 5048,
      sha256:
          '49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb',
    ),
  ],
);

final class _ModelManifest {
  _ModelManifest({
    required this.language,
    required this.modelType,
    required this.files,
  });

  final VoiceLanguage language;
  final String modelType;
  final List<_ModelFile> files;

  int get totalBytes => files.fold(0, (total, file) => total + file.size);
}

final class _ModelFile {
  const _ModelFile({
    required this.localName,
    required this.uri,
    required this.size,
    required this.sha256,
  });

  final String localName;
  final Uri uri;
  final int size;
  final String sha256;
}
