/// Native Drift constructors kept out of the web-safe store implementation.
library;

import 'dart:io';

import 'package:drift/native.dart';

import 'database.dart';
import 'drift_store.dart';

DriftCoachStore openNativeCoachStoreFile(File file) =>
    DriftCoachStore(CoachDatabase(NativeDatabase(file)));

DriftCoachStore openNativeCoachStoreMemory() =>
    DriftCoachStore(CoachDatabase(NativeDatabase.memory()));
