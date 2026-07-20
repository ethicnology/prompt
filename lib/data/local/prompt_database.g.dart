// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prompt_database.dart';

// ignore_for_file: type=lint
class $ServerProfilesTable extends ServerProfiles
    with TableInfo<$ServerProfilesTable, ServerProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastAccessedAtMillisMeta =
      const VerificationMeta('lastAccessedAtMillis');
  @override
  late final GeneratedColumn<int> lastAccessedAtMillis = GeneratedColumn<int>(
    'last_accessed_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    origin,
    username,
    lastAccessedAtMillis,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'server_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServerProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('last_accessed_at_millis')) {
      context.handle(
        _lastAccessedAtMillisMeta,
        lastAccessedAtMillis.isAcceptableOrUnknown(
          data['last_accessed_at_millis']!,
          _lastAccessedAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedAtMillisMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      lastAccessedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessed_at_millis'],
      )!,
    );
  }

  @override
  $ServerProfilesTable createAlias(String alias) {
    return $ServerProfilesTable(attachedDatabase, alias);
  }
}

class ServerProfile extends DataClass implements Insertable<ServerProfile> {
  final String id;
  final String origin;
  final String? username;
  final int lastAccessedAtMillis;
  const ServerProfile({
    required this.id,
    required this.origin,
    this.username,
    required this.lastAccessedAtMillis,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['last_accessed_at_millis'] = Variable<int>(lastAccessedAtMillis);
    return map;
  }

  ServerProfilesCompanion toCompanion(bool nullToAbsent) {
    return ServerProfilesCompanion(
      id: Value(id),
      origin: Value(origin),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      lastAccessedAtMillis: Value(lastAccessedAtMillis),
    );
  }

  factory ServerProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerProfile(
      id: serializer.fromJson<String>(json['id']),
      origin: serializer.fromJson<String>(json['origin']),
      username: serializer.fromJson<String?>(json['username']),
      lastAccessedAtMillis: serializer.fromJson<int>(
        json['lastAccessedAtMillis'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'origin': serializer.toJson<String>(origin),
      'username': serializer.toJson<String?>(username),
      'lastAccessedAtMillis': serializer.toJson<int>(lastAccessedAtMillis),
    };
  }

  ServerProfile copyWith({
    String? id,
    String? origin,
    Value<String?> username = const Value.absent(),
    int? lastAccessedAtMillis,
  }) => ServerProfile(
    id: id ?? this.id,
    origin: origin ?? this.origin,
    username: username.present ? username.value : this.username,
    lastAccessedAtMillis: lastAccessedAtMillis ?? this.lastAccessedAtMillis,
  );
  ServerProfile copyWithCompanion(ServerProfilesCompanion data) {
    return ServerProfile(
      id: data.id.present ? data.id.value : this.id,
      origin: data.origin.present ? data.origin.value : this.origin,
      username: data.username.present ? data.username.value : this.username,
      lastAccessedAtMillis: data.lastAccessedAtMillis.present
          ? data.lastAccessedAtMillis.value
          : this.lastAccessedAtMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerProfile(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('username: $username, ')
          ..write('lastAccessedAtMillis: $lastAccessedAtMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, origin, username, lastAccessedAtMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerProfile &&
          other.id == this.id &&
          other.origin == this.origin &&
          other.username == this.username &&
          other.lastAccessedAtMillis == this.lastAccessedAtMillis);
}

class ServerProfilesCompanion extends UpdateCompanion<ServerProfile> {
  final Value<String> id;
  final Value<String> origin;
  final Value<String?> username;
  final Value<int> lastAccessedAtMillis;
  final Value<int> rowid;
  const ServerProfilesCompanion({
    this.id = const Value.absent(),
    this.origin = const Value.absent(),
    this.username = const Value.absent(),
    this.lastAccessedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServerProfilesCompanion.insert({
    required String id,
    required String origin,
    this.username = const Value.absent(),
    required int lastAccessedAtMillis,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       origin = Value(origin),
       lastAccessedAtMillis = Value(lastAccessedAtMillis);
  static Insertable<ServerProfile> custom({
    Expression<String>? id,
    Expression<String>? origin,
    Expression<String>? username,
    Expression<int>? lastAccessedAtMillis,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (origin != null) 'origin': origin,
      if (username != null) 'username': username,
      if (lastAccessedAtMillis != null)
        'last_accessed_at_millis': lastAccessedAtMillis,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServerProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? origin,
    Value<String?>? username,
    Value<int>? lastAccessedAtMillis,
    Value<int>? rowid,
  }) {
    return ServerProfilesCompanion(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      username: username ?? this.username,
      lastAccessedAtMillis: lastAccessedAtMillis ?? this.lastAccessedAtMillis,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (lastAccessedAtMillis.present) {
      map['last_accessed_at_millis'] = Variable<int>(
        lastAccessedAtMillis.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerProfilesCompanion(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('username: $username, ')
          ..write('lastAccessedAtMillis: $lastAccessedAtMillis, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueuedPromptsTable extends QueuedPrompts
    with TableInfo<$QueuedPromptsTable, QueuedPrompt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueuedPromptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverProfileIdMeta = const VerificationMeta(
    'serverProfileId',
  );
  @override
  late final GeneratedColumn<String> serverProfileId = GeneratedColumn<String>(
    'server_profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directoryMeta = const VerificationMeta(
    'directory',
  );
  @override
  late final GeneratedColumn<String> directory = GeneratedColumn<String>(
    'directory',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptTextMeta = const VerificationMeta(
    'promptText',
  );
  @override
  late final GeneratedColumn<String> promptText = GeneratedColumn<String>(
    'prompt_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pauseReasonMeta = const VerificationMeta(
    'pauseReason',
  );
  @override
  late final GeneratedColumn<String> pauseReason = GeneratedColumn<String>(
    'pause_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMillisMeta = const VerificationMeta(
    'createdAtMillis',
  );
  @override
  late final GeneratedColumn<int> createdAtMillis = GeneratedColumn<int>(
    'created_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMillisMeta = const VerificationMeta(
    'updatedAtMillis',
  );
  @override
  late final GeneratedColumn<int> updatedAtMillis = GeneratedColumn<int>(
    'updated_at_millis',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sendingStartedAtMillisMeta =
      const VerificationMeta('sendingStartedAtMillis');
  @override
  late final GeneratedColumn<int> sendingStartedAtMillis = GeneratedColumn<int>(
    'sending_started_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMillisMeta =
      const VerificationMeta('acknowledgedAtMillis');
  @override
  late final GeneratedColumn<int> acknowledgedAtMillis = GeneratedColumn<int>(
    'acknowledged_at_millis',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverProfileId,
    sessionId,
    directory,
    position,
    promptText,
    state,
    pauseReason,
    attemptCount,
    createdAtMillis,
    updatedAtMillis,
    sendingStartedAtMillis,
    acknowledgedAtMillis,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queued_prompts';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedPrompt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_profile_id')) {
      context.handle(
        _serverProfileIdMeta,
        serverProfileId.isAcceptableOrUnknown(
          data['server_profile_id']!,
          _serverProfileIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverProfileIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('directory')) {
      context.handle(
        _directoryMeta,
        directory.isAcceptableOrUnknown(data['directory']!, _directoryMeta),
      );
    } else if (isInserting) {
      context.missing(_directoryMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('prompt_text')) {
      context.handle(
        _promptTextMeta,
        promptText.isAcceptableOrUnknown(data['prompt_text']!, _promptTextMeta),
      );
    } else if (isInserting) {
      context.missing(_promptTextMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('pause_reason')) {
      context.handle(
        _pauseReasonMeta,
        pauseReason.isAcceptableOrUnknown(
          data['pause_reason']!,
          _pauseReasonMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('created_at_millis')) {
      context.handle(
        _createdAtMillisMeta,
        createdAtMillis.isAcceptableOrUnknown(
          data['created_at_millis']!,
          _createdAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMillisMeta);
    }
    if (data.containsKey('updated_at_millis')) {
      context.handle(
        _updatedAtMillisMeta,
        updatedAtMillis.isAcceptableOrUnknown(
          data['updated_at_millis']!,
          _updatedAtMillisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMillisMeta);
    }
    if (data.containsKey('sending_started_at_millis')) {
      context.handle(
        _sendingStartedAtMillisMeta,
        sendingStartedAtMillis.isAcceptableOrUnknown(
          data['sending_started_at_millis']!,
          _sendingStartedAtMillisMeta,
        ),
      );
    }
    if (data.containsKey('acknowledged_at_millis')) {
      context.handle(
        _acknowledgedAtMillisMeta,
        acknowledgedAtMillis.isAcceptableOrUnknown(
          data['acknowledged_at_millis']!,
          _acknowledgedAtMillisMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {serverProfileId, sessionId, position},
  ];
  @override
  QueuedPrompt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedPrompt(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverProfileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_profile_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      directory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      promptText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_text'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      pauseReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pause_reason'],
      ),
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      createdAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_millis'],
      )!,
      updatedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_millis'],
      )!,
      sendingStartedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sending_started_at_millis'],
      ),
      acknowledgedAtMillis: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acknowledged_at_millis'],
      ),
    );
  }

  @override
  $QueuedPromptsTable createAlias(String alias) {
    return $QueuedPromptsTable(attachedDatabase, alias);
  }
}

class QueuedPrompt extends DataClass implements Insertable<QueuedPrompt> {
  final String id;
  final String serverProfileId;
  final String sessionId;
  final String directory;
  final int position;
  final String promptText;
  final String state;
  final String? pauseReason;
  final int attemptCount;
  final int createdAtMillis;
  final int updatedAtMillis;
  final int? sendingStartedAtMillis;
  final int? acknowledgedAtMillis;
  const QueuedPrompt({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.directory,
    required this.position,
    required this.promptText,
    required this.state,
    this.pauseReason,
    required this.attemptCount,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.sendingStartedAtMillis,
    this.acknowledgedAtMillis,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['server_profile_id'] = Variable<String>(serverProfileId);
    map['session_id'] = Variable<String>(sessionId);
    map['directory'] = Variable<String>(directory);
    map['position'] = Variable<int>(position);
    map['prompt_text'] = Variable<String>(promptText);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || pauseReason != null) {
      map['pause_reason'] = Variable<String>(pauseReason);
    }
    map['attempt_count'] = Variable<int>(attemptCount);
    map['created_at_millis'] = Variable<int>(createdAtMillis);
    map['updated_at_millis'] = Variable<int>(updatedAtMillis);
    if (!nullToAbsent || sendingStartedAtMillis != null) {
      map['sending_started_at_millis'] = Variable<int>(sendingStartedAtMillis);
    }
    if (!nullToAbsent || acknowledgedAtMillis != null) {
      map['acknowledged_at_millis'] = Variable<int>(acknowledgedAtMillis);
    }
    return map;
  }

  QueuedPromptsCompanion toCompanion(bool nullToAbsent) {
    return QueuedPromptsCompanion(
      id: Value(id),
      serverProfileId: Value(serverProfileId),
      sessionId: Value(sessionId),
      directory: Value(directory),
      position: Value(position),
      promptText: Value(promptText),
      state: Value(state),
      pauseReason: pauseReason == null && nullToAbsent
          ? const Value.absent()
          : Value(pauseReason),
      attemptCount: Value(attemptCount),
      createdAtMillis: Value(createdAtMillis),
      updatedAtMillis: Value(updatedAtMillis),
      sendingStartedAtMillis: sendingStartedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(sendingStartedAtMillis),
      acknowledgedAtMillis: acknowledgedAtMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAtMillis),
    );
  }

  factory QueuedPrompt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedPrompt(
      id: serializer.fromJson<String>(json['id']),
      serverProfileId: serializer.fromJson<String>(json['serverProfileId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      directory: serializer.fromJson<String>(json['directory']),
      position: serializer.fromJson<int>(json['position']),
      promptText: serializer.fromJson<String>(json['promptText']),
      state: serializer.fromJson<String>(json['state']),
      pauseReason: serializer.fromJson<String?>(json['pauseReason']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      createdAtMillis: serializer.fromJson<int>(json['createdAtMillis']),
      updatedAtMillis: serializer.fromJson<int>(json['updatedAtMillis']),
      sendingStartedAtMillis: serializer.fromJson<int?>(
        json['sendingStartedAtMillis'],
      ),
      acknowledgedAtMillis: serializer.fromJson<int?>(
        json['acknowledgedAtMillis'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverProfileId': serializer.toJson<String>(serverProfileId),
      'sessionId': serializer.toJson<String>(sessionId),
      'directory': serializer.toJson<String>(directory),
      'position': serializer.toJson<int>(position),
      'promptText': serializer.toJson<String>(promptText),
      'state': serializer.toJson<String>(state),
      'pauseReason': serializer.toJson<String?>(pauseReason),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'createdAtMillis': serializer.toJson<int>(createdAtMillis),
      'updatedAtMillis': serializer.toJson<int>(updatedAtMillis),
      'sendingStartedAtMillis': serializer.toJson<int?>(sendingStartedAtMillis),
      'acknowledgedAtMillis': serializer.toJson<int?>(acknowledgedAtMillis),
    };
  }

  QueuedPrompt copyWith({
    String? id,
    String? serverProfileId,
    String? sessionId,
    String? directory,
    int? position,
    String? promptText,
    String? state,
    Value<String?> pauseReason = const Value.absent(),
    int? attemptCount,
    int? createdAtMillis,
    int? updatedAtMillis,
    Value<int?> sendingStartedAtMillis = const Value.absent(),
    Value<int?> acknowledgedAtMillis = const Value.absent(),
  }) => QueuedPrompt(
    id: id ?? this.id,
    serverProfileId: serverProfileId ?? this.serverProfileId,
    sessionId: sessionId ?? this.sessionId,
    directory: directory ?? this.directory,
    position: position ?? this.position,
    promptText: promptText ?? this.promptText,
    state: state ?? this.state,
    pauseReason: pauseReason.present ? pauseReason.value : this.pauseReason,
    attemptCount: attemptCount ?? this.attemptCount,
    createdAtMillis: createdAtMillis ?? this.createdAtMillis,
    updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    sendingStartedAtMillis: sendingStartedAtMillis.present
        ? sendingStartedAtMillis.value
        : this.sendingStartedAtMillis,
    acknowledgedAtMillis: acknowledgedAtMillis.present
        ? acknowledgedAtMillis.value
        : this.acknowledgedAtMillis,
  );
  QueuedPrompt copyWithCompanion(QueuedPromptsCompanion data) {
    return QueuedPrompt(
      id: data.id.present ? data.id.value : this.id,
      serverProfileId: data.serverProfileId.present
          ? data.serverProfileId.value
          : this.serverProfileId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      directory: data.directory.present ? data.directory.value : this.directory,
      position: data.position.present ? data.position.value : this.position,
      promptText: data.promptText.present
          ? data.promptText.value
          : this.promptText,
      state: data.state.present ? data.state.value : this.state,
      pauseReason: data.pauseReason.present
          ? data.pauseReason.value
          : this.pauseReason,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      createdAtMillis: data.createdAtMillis.present
          ? data.createdAtMillis.value
          : this.createdAtMillis,
      updatedAtMillis: data.updatedAtMillis.present
          ? data.updatedAtMillis.value
          : this.updatedAtMillis,
      sendingStartedAtMillis: data.sendingStartedAtMillis.present
          ? data.sendingStartedAtMillis.value
          : this.sendingStartedAtMillis,
      acknowledgedAtMillis: data.acknowledgedAtMillis.present
          ? data.acknowledgedAtMillis.value
          : this.acknowledgedAtMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedPrompt(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('directory: $directory, ')
          ..write('position: $position, ')
          ..write('promptText: $promptText, ')
          ..write('state: $state, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('updatedAtMillis: $updatedAtMillis, ')
          ..write('sendingStartedAtMillis: $sendingStartedAtMillis, ')
          ..write('acknowledgedAtMillis: $acknowledgedAtMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverProfileId,
    sessionId,
    directory,
    position,
    promptText,
    state,
    pauseReason,
    attemptCount,
    createdAtMillis,
    updatedAtMillis,
    sendingStartedAtMillis,
    acknowledgedAtMillis,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedPrompt &&
          other.id == this.id &&
          other.serverProfileId == this.serverProfileId &&
          other.sessionId == this.sessionId &&
          other.directory == this.directory &&
          other.position == this.position &&
          other.promptText == this.promptText &&
          other.state == this.state &&
          other.pauseReason == this.pauseReason &&
          other.attemptCount == this.attemptCount &&
          other.createdAtMillis == this.createdAtMillis &&
          other.updatedAtMillis == this.updatedAtMillis &&
          other.sendingStartedAtMillis == this.sendingStartedAtMillis &&
          other.acknowledgedAtMillis == this.acknowledgedAtMillis);
}

class QueuedPromptsCompanion extends UpdateCompanion<QueuedPrompt> {
  final Value<String> id;
  final Value<String> serverProfileId;
  final Value<String> sessionId;
  final Value<String> directory;
  final Value<int> position;
  final Value<String> promptText;
  final Value<String> state;
  final Value<String?> pauseReason;
  final Value<int> attemptCount;
  final Value<int> createdAtMillis;
  final Value<int> updatedAtMillis;
  final Value<int?> sendingStartedAtMillis;
  final Value<int?> acknowledgedAtMillis;
  final Value<int> rowid;
  const QueuedPromptsCompanion({
    this.id = const Value.absent(),
    this.serverProfileId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.directory = const Value.absent(),
    this.position = const Value.absent(),
    this.promptText = const Value.absent(),
    this.state = const Value.absent(),
    this.pauseReason = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.createdAtMillis = const Value.absent(),
    this.updatedAtMillis = const Value.absent(),
    this.sendingStartedAtMillis = const Value.absent(),
    this.acknowledgedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueuedPromptsCompanion.insert({
    required String id,
    required String serverProfileId,
    required String sessionId,
    required String directory,
    required int position,
    required String promptText,
    required String state,
    this.pauseReason = const Value.absent(),
    this.attemptCount = const Value.absent(),
    required int createdAtMillis,
    required int updatedAtMillis,
    this.sendingStartedAtMillis = const Value.absent(),
    this.acknowledgedAtMillis = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       serverProfileId = Value(serverProfileId),
       sessionId = Value(sessionId),
       directory = Value(directory),
       position = Value(position),
       promptText = Value(promptText),
       state = Value(state),
       createdAtMillis = Value(createdAtMillis),
       updatedAtMillis = Value(updatedAtMillis);
  static Insertable<QueuedPrompt> custom({
    Expression<String>? id,
    Expression<String>? serverProfileId,
    Expression<String>? sessionId,
    Expression<String>? directory,
    Expression<int>? position,
    Expression<String>? promptText,
    Expression<String>? state,
    Expression<String>? pauseReason,
    Expression<int>? attemptCount,
    Expression<int>? createdAtMillis,
    Expression<int>? updatedAtMillis,
    Expression<int>? sendingStartedAtMillis,
    Expression<int>? acknowledgedAtMillis,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverProfileId != null) 'server_profile_id': serverProfileId,
      if (sessionId != null) 'session_id': sessionId,
      if (directory != null) 'directory': directory,
      if (position != null) 'position': position,
      if (promptText != null) 'prompt_text': promptText,
      if (state != null) 'state': state,
      if (pauseReason != null) 'pause_reason': pauseReason,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (createdAtMillis != null) 'created_at_millis': createdAtMillis,
      if (updatedAtMillis != null) 'updated_at_millis': updatedAtMillis,
      if (sendingStartedAtMillis != null)
        'sending_started_at_millis': sendingStartedAtMillis,
      if (acknowledgedAtMillis != null)
        'acknowledged_at_millis': acknowledgedAtMillis,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueuedPromptsCompanion copyWith({
    Value<String>? id,
    Value<String>? serverProfileId,
    Value<String>? sessionId,
    Value<String>? directory,
    Value<int>? position,
    Value<String>? promptText,
    Value<String>? state,
    Value<String?>? pauseReason,
    Value<int>? attemptCount,
    Value<int>? createdAtMillis,
    Value<int>? updatedAtMillis,
    Value<int?>? sendingStartedAtMillis,
    Value<int?>? acknowledgedAtMillis,
    Value<int>? rowid,
  }) {
    return QueuedPromptsCompanion(
      id: id ?? this.id,
      serverProfileId: serverProfileId ?? this.serverProfileId,
      sessionId: sessionId ?? this.sessionId,
      directory: directory ?? this.directory,
      position: position ?? this.position,
      promptText: promptText ?? this.promptText,
      state: state ?? this.state,
      pauseReason: pauseReason ?? this.pauseReason,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      sendingStartedAtMillis:
          sendingStartedAtMillis ?? this.sendingStartedAtMillis,
      acknowledgedAtMillis: acknowledgedAtMillis ?? this.acknowledgedAtMillis,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverProfileId.present) {
      map['server_profile_id'] = Variable<String>(serverProfileId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (directory.present) {
      map['directory'] = Variable<String>(directory.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (promptText.present) {
      map['prompt_text'] = Variable<String>(promptText.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (pauseReason.present) {
      map['pause_reason'] = Variable<String>(pauseReason.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (createdAtMillis.present) {
      map['created_at_millis'] = Variable<int>(createdAtMillis.value);
    }
    if (updatedAtMillis.present) {
      map['updated_at_millis'] = Variable<int>(updatedAtMillis.value);
    }
    if (sendingStartedAtMillis.present) {
      map['sending_started_at_millis'] = Variable<int>(
        sendingStartedAtMillis.value,
      );
    }
    if (acknowledgedAtMillis.present) {
      map['acknowledged_at_millis'] = Variable<int>(acknowledgedAtMillis.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueuedPromptsCompanion(')
          ..write('id: $id, ')
          ..write('serverProfileId: $serverProfileId, ')
          ..write('sessionId: $sessionId, ')
          ..write('directory: $directory, ')
          ..write('position: $position, ')
          ..write('promptText: $promptText, ')
          ..write('state: $state, ')
          ..write('pauseReason: $pauseReason, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('createdAtMillis: $createdAtMillis, ')
          ..write('updatedAtMillis: $updatedAtMillis, ')
          ..write('sendingStartedAtMillis: $sendingStartedAtMillis, ')
          ..write('acknowledgedAtMillis: $acknowledgedAtMillis, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PromptDatabase extends GeneratedDatabase {
  _$PromptDatabase(QueryExecutor e) : super(e);
  $PromptDatabaseManager get managers => $PromptDatabaseManager(this);
  late final $ServerProfilesTable serverProfiles = $ServerProfilesTable(this);
  late final $QueuedPromptsTable queuedPrompts = $QueuedPromptsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    serverProfiles,
    queuedPrompts,
  ];
}

typedef $$ServerProfilesTableCreateCompanionBuilder =
    ServerProfilesCompanion Function({
      required String id,
      required String origin,
      Value<String?> username,
      required int lastAccessedAtMillis,
      Value<int> rowid,
    });
typedef $$ServerProfilesTableUpdateCompanionBuilder =
    ServerProfilesCompanion Function({
      Value<String> id,
      Value<String> origin,
      Value<String?> username,
      Value<int> lastAccessedAtMillis,
      Value<int> rowid,
    });

class $$ServerProfilesTableFilterComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServerProfilesTableOrderingComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServerProfilesTableAnnotationComposer
    extends Composer<_$PromptDatabase, $ServerProfilesTable> {
  $$ServerProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<int> get lastAccessedAtMillis => $composableBuilder(
    column: $table.lastAccessedAtMillis,
    builder: (column) => column,
  );
}

class $$ServerProfilesTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $ServerProfilesTable,
          ServerProfile,
          $$ServerProfilesTableFilterComposer,
          $$ServerProfilesTableOrderingComposer,
          $$ServerProfilesTableAnnotationComposer,
          $$ServerProfilesTableCreateCompanionBuilder,
          $$ServerProfilesTableUpdateCompanionBuilder,
          (
            ServerProfile,
            BaseReferences<
              _$PromptDatabase,
              $ServerProfilesTable,
              ServerProfile
            >,
          ),
          ServerProfile,
          PrefetchHooks Function()
        > {
  $$ServerProfilesTableTableManager(
    _$PromptDatabase db,
    $ServerProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServerProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServerProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServerProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<int> lastAccessedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServerProfilesCompanion(
                id: id,
                origin: origin,
                username: username,
                lastAccessedAtMillis: lastAccessedAtMillis,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String origin,
                Value<String?> username = const Value.absent(),
                required int lastAccessedAtMillis,
                Value<int> rowid = const Value.absent(),
              }) => ServerProfilesCompanion.insert(
                id: id,
                origin: origin,
                username: username,
                lastAccessedAtMillis: lastAccessedAtMillis,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServerProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $ServerProfilesTable,
      ServerProfile,
      $$ServerProfilesTableFilterComposer,
      $$ServerProfilesTableOrderingComposer,
      $$ServerProfilesTableAnnotationComposer,
      $$ServerProfilesTableCreateCompanionBuilder,
      $$ServerProfilesTableUpdateCompanionBuilder,
      (
        ServerProfile,
        BaseReferences<_$PromptDatabase, $ServerProfilesTable, ServerProfile>,
      ),
      ServerProfile,
      PrefetchHooks Function()
    >;
typedef $$QueuedPromptsTableCreateCompanionBuilder =
    QueuedPromptsCompanion Function({
      required String id,
      required String serverProfileId,
      required String sessionId,
      required String directory,
      required int position,
      required String promptText,
      required String state,
      Value<String?> pauseReason,
      Value<int> attemptCount,
      required int createdAtMillis,
      required int updatedAtMillis,
      Value<int?> sendingStartedAtMillis,
      Value<int?> acknowledgedAtMillis,
      Value<int> rowid,
    });
typedef $$QueuedPromptsTableUpdateCompanionBuilder =
    QueuedPromptsCompanion Function({
      Value<String> id,
      Value<String> serverProfileId,
      Value<String> sessionId,
      Value<String> directory,
      Value<int> position,
      Value<String> promptText,
      Value<String> state,
      Value<String?> pauseReason,
      Value<int> attemptCount,
      Value<int> createdAtMillis,
      Value<int> updatedAtMillis,
      Value<int?> sendingStartedAtMillis,
      Value<int?> acknowledgedAtMillis,
      Value<int> rowid,
    });

class $$QueuedPromptsTableFilterComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueuedPromptsTableOrderingComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directory => $composableBuilder(
    column: $table.directory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueuedPromptsTableAnnotationComposer
    extends Composer<_$PromptDatabase, $QueuedPromptsTable> {
  $$QueuedPromptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverProfileId => $composableBuilder(
    column: $table.serverProfileId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get directory =>
      $composableBuilder(column: $table.directory, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get promptText => $composableBuilder(
    column: $table.promptText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get pauseReason => $composableBuilder(
    column: $table.pauseReason,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMillis => $composableBuilder(
    column: $table.createdAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMillis => $composableBuilder(
    column: $table.updatedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sendingStartedAtMillis => $composableBuilder(
    column: $table.sendingStartedAtMillis,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acknowledgedAtMillis => $composableBuilder(
    column: $table.acknowledgedAtMillis,
    builder: (column) => column,
  );
}

class $$QueuedPromptsTableTableManager
    extends
        RootTableManager<
          _$PromptDatabase,
          $QueuedPromptsTable,
          QueuedPrompt,
          $$QueuedPromptsTableFilterComposer,
          $$QueuedPromptsTableOrderingComposer,
          $$QueuedPromptsTableAnnotationComposer,
          $$QueuedPromptsTableCreateCompanionBuilder,
          $$QueuedPromptsTableUpdateCompanionBuilder,
          (
            QueuedPrompt,
            BaseReferences<_$PromptDatabase, $QueuedPromptsTable, QueuedPrompt>,
          ),
          QueuedPrompt,
          PrefetchHooks Function()
        > {
  $$QueuedPromptsTableTableManager(
    _$PromptDatabase db,
    $QueuedPromptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueuedPromptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueuedPromptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueuedPromptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> serverProfileId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> directory = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> promptText = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> pauseReason = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<int> createdAtMillis = const Value.absent(),
                Value<int> updatedAtMillis = const Value.absent(),
                Value<int?> sendingStartedAtMillis = const Value.absent(),
                Value<int?> acknowledgedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedPromptsCompanion(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                directory: directory,
                position: position,
                promptText: promptText,
                state: state,
                pauseReason: pauseReason,
                attemptCount: attemptCount,
                createdAtMillis: createdAtMillis,
                updatedAtMillis: updatedAtMillis,
                sendingStartedAtMillis: sendingStartedAtMillis,
                acknowledgedAtMillis: acknowledgedAtMillis,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String serverProfileId,
                required String sessionId,
                required String directory,
                required int position,
                required String promptText,
                required String state,
                Value<String?> pauseReason = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                required int createdAtMillis,
                required int updatedAtMillis,
                Value<int?> sendingStartedAtMillis = const Value.absent(),
                Value<int?> acknowledgedAtMillis = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedPromptsCompanion.insert(
                id: id,
                serverProfileId: serverProfileId,
                sessionId: sessionId,
                directory: directory,
                position: position,
                promptText: promptText,
                state: state,
                pauseReason: pauseReason,
                attemptCount: attemptCount,
                createdAtMillis: createdAtMillis,
                updatedAtMillis: updatedAtMillis,
                sendingStartedAtMillis: sendingStartedAtMillis,
                acknowledgedAtMillis: acknowledgedAtMillis,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueuedPromptsTableProcessedTableManager =
    ProcessedTableManager<
      _$PromptDatabase,
      $QueuedPromptsTable,
      QueuedPrompt,
      $$QueuedPromptsTableFilterComposer,
      $$QueuedPromptsTableOrderingComposer,
      $$QueuedPromptsTableAnnotationComposer,
      $$QueuedPromptsTableCreateCompanionBuilder,
      $$QueuedPromptsTableUpdateCompanionBuilder,
      (
        QueuedPrompt,
        BaseReferences<_$PromptDatabase, $QueuedPromptsTable, QueuedPrompt>,
      ),
      QueuedPrompt,
      PrefetchHooks Function()
    >;

class $PromptDatabaseManager {
  final _$PromptDatabase _db;
  $PromptDatabaseManager(this._db);
  $$ServerProfilesTableTableManager get serverProfiles =>
      $$ServerProfilesTableTableManager(_db, _db.serverProfiles);
  $$QueuedPromptsTableTableManager get queuedPrompts =>
      $$QueuedPromptsTableTableManager(_db, _db.queuedPrompts);
}
