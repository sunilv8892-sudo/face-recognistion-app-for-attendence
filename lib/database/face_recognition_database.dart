import 'package:drift/drift.dart';
import 'database_connection.dart' as db_connection;
import 'dart:math' as math;
import 'dart:convert';

part 'face_recognition_database.g.dart';

/// Student table
class Students extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get rollNumber => text().unique()();
  TextColumn get studentClass => text()();
  DateTimeColumn get enrollmentDate => dateTime()();
}

/// Face embeddings table with vector support
class FaceEmbeddings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get vector => text()(); // JSON string of float array
  DateTimeColumn get captureDate => dateTime()();
}

/// Attendance records
class Attendance extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get studentId =>
      integer().references(Students, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  TextColumn get time => text().nullable()();
  TextColumn get status => text()(); // 'present', 'absent', 'late'
  DateTimeColumn get recordedAt => dateTime()();
}

/// Drift database class
@DriftDatabase(tables: [Students, FaceEmbeddings, Attendance])
class FaceRecognitionDatabase extends _$FaceRecognitionDatabase {
  FaceRecognitionDatabase()
    : super(
        db_connection.DatabaseConnection.instance.openConnection(
          'face_recognition.db',
        ),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Create vector indexes if extension is available
      try {
        await customStatement(
          'CREATE VIRTUAL TABLE face_embeddings_vec USING vec0(vector(512));',
        );
      } catch (e) {
        print('Vector extension not available for indexing: $e');
      }
    },
  );

  // Student operations
  Future<int> insertStudent(StudentsCompanion student) =>
      into(students).insert(student);

  Future<List<Student>> getAllStudents() => select(students).get();

  Future<Student?> getStudentById(int id) =>
      (select(students)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<Student>> searchStudentsByName(String query) =>
      (select(students)..where((s) => s.name.contains(query))).get();

  Future<int> updateStudent(int id, StudentsCompanion student) =>
      (update(students)..where((s) => s.id.equals(id))).write(student);

  Future<int> deleteStudent(int id) =>
      (delete(students)..where((s) => s.id.equals(id))).go();

  // Face embedding operations
  Future<int> insertEmbedding(FaceEmbeddingsCompanion embedding) =>
      into(faceEmbeddings).insert(embedding);

  Future<List<FaceEmbedding>> getEmbeddingsForStudent(int studentId) => (select(
    faceEmbeddings,
  )..where((e) => e.studentId.equals(studentId))).get();

  Future<List<FaceEmbedding>> getAllEmbeddings() =>
      select(faceEmbeddings).get();

  // Vector similarity search using cosine similarity
  Future<List<FaceEmbedding>> findSimilarEmbeddings(
    List<double> queryVector,
    double threshold,
  ) async {
    final embeddings = await getAllEmbeddings();
    final similarities = <MapEntry<FaceEmbedding, double>>[];

    for (final embedding in embeddings) {
      final vector = _parseVector(embedding.vector);
      final similarity = _cosineSimilarity(queryVector, vector);
      if (similarity >= threshold) {
        similarities.add(MapEntry(embedding, similarity));
      }
    }

    // Sort by similarity (highest first)
    similarities.sort((a, b) => b.value.compareTo(a.value));
    return similarities.map((e) => e.key).toList();
  }

  // Attendance operations
  Future<int> insertAttendance(AttendanceCompanion companion) =>
      into(attendance).insert(companion);

  Future<List<AttendanceData>> getAttendanceForStudent(int studentId) =>
      (select(attendance)..where((a) => a.studentId.equals(studentId))).get();

  Future<List<AttendanceData>> getAttendanceForDate(DateTime date) {
    // Compare only the date part (year, month, day) ignoring time
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return (select(attendance)
          ..where((a) =>
              a.date.isBiggerOrEqualValue(startOfDay) &
              a.date.isSmallerOrEqualValue(endOfDay)))
        .get();
  }

  Future<AttendanceData?> getAttendanceForStudentOnDate(
    int studentId,
    DateTime date,
  ) =>
      (select(attendance)
            ..where((a) => a.studentId.equals(studentId) & a.date.equals(date)))
          .getSingleOrNull();

  // Helper methods
  List<double> _parseVector(String vectorStr) {
    // Parse JSON string to List<double>
    try {
      final decoded = jsonDecode(vectorStr);
      if (decoded is List) {
        return List<double>.from(decoded.map((v) => (v as num).toDouble()));
      }
      throw FormatException('Invalid vector format');
    } catch (e) {
      print('⚠️ Error parsing vector: $e');
      print('   Vector string: $vectorStr');
      return [];
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = normA > 0 ? math.sqrt(normA) : 0;
    normB = normB > 0 ? math.sqrt(normB) : 0;

    return normA == 0 || normB == 0 ? 0.0 : dotProduct / (normA * normB);
  }
}
