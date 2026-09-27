import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// 1. DOMAIN DATA MODELS & ENUMS
// ============================================================================

enum StudentStatus { active, left, demo }
enum AttendanceStatus { present, absent, late }
enum FeeStatus { paid, partial, unpaid }
enum PaymentMode { cash, upi, cheque, netBanking }
enum InquiryStatus { newInquiry, demoScheduled, joined, closed }

class Batch {
  final int? id;
  final String name;
  final String subject;
  final String timing;
  final double feeAmount;
  final String billingCycle; // "Monthly" or "Per Class"

  Batch({
    this.id,
    required this.name,
    required this.subject,
    required this.timing,
    required this.feeAmount,
    this.billingCycle = 'Monthly',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'subject': subject,
    'timing': timing,
    'fee_amount': feeAmount,
    'billing_cycle': billingCycle,
  };

  factory Batch.fromMap(Map<String, dynamic> map) => Batch(
    id: map['id'] as int?,
    name: map['name'] as String,
    subject: map['subject'] as String,
    timing: map['timing'] as String,
    feeAmount: (map['fee_amount'] as num).toDouble(),
    billingCycle: map['billing_cycle'] as String? ?? 'Monthly',
  );
}

class Student {
  final int? id;
  final int batchId;
  final String name;
  final String parentName;
  final String parentPhone; // Expected with +91 or 10 digits
  final String joiningDate;
  final StudentStatus status;

  Student({
    this.id,
    required this.batchId,
    required this.name,
    required this.parentName,
    required this.parentPhone,
    required this.joiningDate,
    this.status = StudentStatus.active,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'batch_id': batchId,
    'name': name,
    'parent_name': parentName,
    'parent_phone': parentPhone,
    'joining_date': joiningDate,
    'status': status.name,
  };

  factory Student.fromMap(Map<String, dynamic> map) => Student(
    id: map['id'] as int?,
    batchId: map['batch_id'] as int,
    name: map['name'] as String,
    parentName: map['parent_name'] as String,
    parentPhone: map['parent_phone'] as String,
    joiningDate: map['joining_date'] as String,
    status: StudentStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => StudentStatus.active,
    ),
  );
}

class Attendance {
  final int? id;
  final int studentId;
  final int batchId;
  final String date; // YYYY-MM-DD
  final AttendanceStatus status;

  Attendance({
    this.id,
    required this.studentId,
    required this.batchId,
    required this.date,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'student_id': studentId,
    'batch_id': batchId,
    'date': date,
    'status': status.name,
  };

  factory Attendance.fromMap(Map<String, dynamic> map) => Attendance(
    id: map['id'] as int?,
    studentId: map['student_id'] as int,
    batchId: map['batch_id'] as int,
    date: map['date'] as String,
    status: AttendanceStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => AttendanceStatus.present,
    ),
  );
}

class FeeRecord {
  final int? id;
  final int studentId;
  final int batchId;
  final String monthYear; // e.g., "Oct 2026"
  final double totalDue;
  final double amountPaid;
  final double dueBalance;
  final String dueDate; // YYYY-MM-DD
  final FeeStatus status;

  FeeRecord({
    this.id,
    required this.studentId,
    required this.batchId,
    required this.monthYear,
    required this.totalDue,
    required this.amountPaid,
    required this.dueBalance,
    required this.dueDate,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'student_id': studentId,
    'batch_id': batchId,
    'month_year': monthYear,
    'total_due': totalDue,
    'amount_paid': amountPaid,
    'due_balance': dueBalance,
    'due_date': dueDate,
    'status': status.name,
  };

  factory FeeRecord.fromMap(Map<String, dynamic> map) => FeeRecord(
    id: map['id'] as int?,
    studentId: map['student_id'] as int,
    batchId: map['batch_id'] as int,
    monthYear: map['month_year'] as String,
    totalDue: (map['total_due'] as num).toDouble(),
    amountPaid: (map['amount_paid'] as num).toDouble(),
    dueBalance: (map['due_balance'] as num).toDouble(),
    dueDate: map['due_date'] as String,
    status: FeeStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => FeeStatus.unpaid,
    ),
  );
}

class FeeTransaction {
  final int? id;
  final int feeRecordId;
  final double amount;
  final PaymentMode paymentMode;
  final String transactionDate; // ISO-8601 string
  final String receiptNumber;

  FeeTransaction({
    this.id,
    required this.feeRecordId,
    required this.amount,
    required this.paymentMode,
    required this.transactionDate,
    required this.receiptNumber,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'fee_record_id': feeRecordId,
    'amount': amount,
    'payment_mode': paymentMode.name,
    'transaction_date': transactionDate,
    'receipt_number': receiptNumber,
  };

  factory FeeTransaction.fromMap(Map<String, dynamic> map) => FeeTransaction(
    id: map['id'] as int?,
    feeRecordId: map['fee_record_id'] as int,
    amount: (map['amount'] as num).toDouble(),
    paymentMode: PaymentMode.values.firstWhere(
      (e) => e.name == map['payment_mode'],
      orElse: () => PaymentMode.cash,
    ),
    transactionDate: map['transaction_date'] as String,
    receiptNumber: map['receipt_number'] as String,
  );
}

class Inquiry {
  final int? id;
  final String studentName;
  final String parentPhone;
  final String gradeSubject;
  final InquiryStatus status;
  final String notes;

  Inquiry({
    this.id,
    required this.studentName,
    required this.parentPhone,
    required this.gradeSubject,
    this.status = InquiryStatus.newInquiry,
    required this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'student_name': studentName,
    'parent_phone': parentPhone,
    'grade_subject': gradeSubject,
    'status': status.name,
    'notes': notes,
  };

  factory Inquiry.fromMap(Map<String, dynamic> map) => Inquiry(
    id: map['id'] as int?,
    studentName: map['student_name'] as String,
    parentPhone: map['parent_phone'] as String,
    gradeSubject: map['grade_subject'] as String,
    status: InquiryStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => InquiryStatus.newInquiry,
    ),
    notes: map['notes'] as String? ?? '',
  );
}

class TestRecord {
  final int? id;
  final int batchId;
  final String testName;
  final double totalMarks;
  final String testDate;

  TestRecord({
    this.id,
    required this.batchId,
    required this.testName,
    required this.totalMarks,
    required this.testDate,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'batch_id': batchId,
    'test_name': testName,
    'total_marks': totalMarks,
    'test_date': testDate,
  };

  factory TestRecord.fromMap(Map<String, dynamic> map) => TestRecord(
    id: map['id'] as int?,
    batchId: map['batch_id'] as int,
    testName: map['test_name'] as String,
    totalMarks: (map['total_marks'] as num).toDouble(),
    testDate: map['test_date'] as String,
  );
}

class StudentTestScore {
  final int? id;
  final int testId;
  final int studentId;
  final double marksObtained;
  final String feedback;

  StudentTestScore({
    this.id,
    required this.testId,
    required this.studentId,
    required this.marksObtained,
    required this.feedback,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'test_id': testId,
    'student_id': studentId,
    'marks_obtained': marksObtained,
    'feedback': feedback,
  };

  factory StudentTestScore.fromMap(Map<String, dynamic> map) => StudentTestScore(
    id: map['id'] as int?,
    testId: map['test_id'] as int,
    studentId: map['student_id'] as int,
    marksObtained: (map['marks_obtained'] as num).toDouble(),
    feedback: map['feedback'] as String? ?? '',
  );
}

// ============================================================================
// 2. SQLITE LOCAL DATABASE LAYER (OFFLINE-FIRST)
// ============================================================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tuition_mate.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Batches Table
    await db.execute('''
      CREATE TABLE batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        subject TEXT NOT NULL,
        timing TEXT NOT NULL,
        fee_amount REAL NOT NULL,
        billing_cycle TEXT NOT NULL
      )
    ''');

    // 2. Students Table
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        parent_name TEXT NOT NULL,
        parent_phone TEXT NOT NULL,
        joining_date TEXT NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (batch_id) REFERENCES batches (id) ON DELETE CASCADE
      )
    ''');

    // 3. Attendance Table
    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        UNIQUE(student_id, date),
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES batches (id) ON DELETE CASCADE
      )
    ''');

    // 4. Fee Records Table
    await db.execute('''
      CREATE TABLE fee_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        batch_id INTEGER NOT NULL,
        month_year TEXT NOT NULL,
        total_due REAL NOT NULL,
        amount_paid REAL NOT NULL,
        due_balance REAL NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (batch_id) REFERENCES batches (id) ON DELETE CASCADE
      )
    ''');

    // 5. Fee Transactions Table
    await db.execute('''
      CREATE TABLE fee_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fee_record_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        transaction_date TEXT NOT NULL,
        receipt_number TEXT NOT NULL,
        FOREIGN KEY (fee_record_id) REFERENCES fee_records (id) ON DELETE CASCADE
      )
    ''');

    // 6. Inquiries Table
    await db.execute('''
      CREATE TABLE inquiries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_name TEXT NOT NULL,
        parent_phone TEXT NOT NULL,
        grade_subject TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT
      )
    ''');

    // 7. Tests Table
    await db.execute('''
      CREATE TABLE tests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_id INTEGER NOT NULL,
        test_name TEXT NOT NULL,
        total_marks REAL NOT NULL,
        test_date TEXT NOT NULL,
        FOREIGN KEY (batch_id) REFERENCES batches (id) ON DELETE CASCADE
      )
    ''');

    // 8. Test Scores Table
    await db.execute('''
      CREATE TABLE student_test_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        test_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        marks_obtained REAL NOT NULL,
        feedback TEXT,
        FOREIGN KEY (test_id) REFERENCES tests (id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');

    // Prepopulate realistic mock data for instant out-of-the-box readiness
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    // Insert initial batches
    final batch1Id = await db.insert('batches', {
      'name': 'Class 10 CBSE Maths',
      'subject': 'Mathematics',
      'timing': '05:00 PM - 06:30 PM (Mon-Fri)',
      'fee_amount': 2500.0,
      'billing_cycle': 'Monthly',
    });

    final batch2Id = await db.insert('batches', {
      'name': 'Class 12 Physics Prodigy',
      'subject': 'Physics',
      'timing': '06:45 PM - 08:15 PM (Tue, Thu, Sat)',
      'fee_amount': 3500.0,
      'billing_cycle': 'Monthly',
    });

    // Insert sample students
    final s1Id = await db.insert('students', {
      'batch_id': batch1Id,
      'name': 'Aarav Sharma',
      'parent_name': 'Rajesh Sharma',
      'parent_phone': '+919876543210',
      'joining_date': '2026-06-15',
      'status': 'active',
    });

    final s2Id = await db.insert('students', {
      'batch_id': batch1Id,
      'name': 'Diya Patel',
      'parent_name': 'Mehul Patel',
      'parent_phone': '+919811223344',
      'joining_date': '2026-07-01',
      'status': 'active',
    });

    final s3Id = await db.insert('students', {
      'batch_id': batch1Id,
      'name': 'Rohan Gupta',
      'parent_name': 'Sanjay Gupta',
      'parent_phone': '+919988776655',
      'joining_date': '2026-08-10',
      'status': 'active',
    });

    // Seed attendance for today
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await db.insert('attendance', {
      'student_id': s1Id,
      'batch_id': batch1Id,
      'date': today,
      'status': 'present',
    });
    await db.insert('attendance', {
      'student_id': s2Id,
      'batch_id': batch1Id,
      'date': today,
      'status': 'absent',
    });

    // Seed fee records
    await db.insert('fee_records', {
      'student_id': s1Id,
      'batch_id': batch1Id,
      'month_year': 'September 2026',
      'total_due': 2500.0,
      'amount_paid': 2500.0,
      'due_balance': 0.0,
      'due_date': '2026-09-05',
      'status': 'paid',
    });

    await db.insert('fee_records', {
      'student_id': s2Id,
      'batch_id': batch1Id,
      'month_year': 'September 2026',
      'total_due': 2500.0,
      'amount_paid': 1000.0,
      'due_balance': 1500.0,
      'due_date': '2026-09-05',
      'status': 'partial',
    });

    await db.insert('fee_records', {
      'student_id': s3Id,
      'batch_id': batch1Id,
      'month_year': 'September 2026',
      'total_due': 2500.0,
      'amount_paid': 0.0,
      'due_balance': 2500.0,
      'due_date': '2026-09-15',
      'status': 'unpaid',
    });

    // Seed sample inquiries
    await db.insert('inquiries', {
      'student_name': 'Kabir Varma',
      'parent_phone': '+919820011223',
      'grade_subject': 'Class 10 Trigonometry crash course',
      'status': 'demoScheduled',
      'notes': 'Requested Saturday demo class. Weak in proofs.',
    });
  }
}

// ============================================================================
// 3. WHATSAPP AUTOMATION & PDF RECEIPT SERVICES
// ============================================================================

class WhatsAppService {
  static const String defaultTutorName = "Prof. Sharma";
  static const String defaultTutorUpi = "tutor@okaxis";

  /// Cleans and sanitizes phone numbers for standard Indian WhatsApp format
  static String formatPhone(String rawPhone) {
    String clean = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length == 10) {
      return '91$clean';
    }
    return clean;
  }

  /// 1-Tap Absent alert generator
  static Future<void> sendAbsentAlert({
    required BuildContext context,
    required String parentPhone,
    required String parentName,
    required String studentName,
    required String batchName,
  }) async {
    final today = DateFormat('dd MMM yyyy').format(DateTime.now());
    final message = "Namaste $parentName Ji,\n"
        "$studentName aaj ($today) ki tuition class ($batchName) me absent hain. "
        "Kripya dhyan dein aur asuvidha se bachne ke liye inform karein.\n\n"
        "- $defaultTutorName";

    await openWhatsApp(phone: parentPhone, message: message, context: context);
  }

  /// 1-Tap Fees Reminder with UPI details
  static Future<void> sendFeeReminder({
    required BuildContext context,
    required String parentPhone,
    required String parentName,
    required String studentName,
    required double dueBalance,
    required String dueDate,
  }) async {
    final message = "Namaste $parentName Ji,\n"
        "$studentName ki is mahine ki tuition fees ₹${dueBalance.toStringAsFixed(0)} due hai. "
        "(Due Date: $dueDate).\n\n"
        "Aap niche diye gaye UPI ID par direct payment kar sakte hain:\n"
        "📲 UPI ID: $defaultTutorUpi\n\n"
        "Payment ke baad kripya screenshot share kar dein. Dhanyawad!\n"
        "- $defaultTutorName";

    await openWhatsApp(phone: parentPhone, message: message, context: context);
  }

  /// Holiday or Reschedule broadcast text
  static Future<void> sendBroadcast({
    required BuildContext context,
    required String phone,
    required String announcement,
    required String batchName,
  }) async {
    final message = "📢 [Class Update: $batchName]\n\n"
        "$announcement\n\n"
        "- $defaultTutorName";
    await openWhatsApp(phone: phone, message: message, context: context);
  }

  /// Opens WhatsApp via intent or deep-link without third-party API dependencies
  static Future<void> openWhatsApp({
    required String phone,
    required String message,
    required BuildContext context,
  }) async {
    final formattedPhone = formatPhone(phone);
    final encodedMsg = Uri.encodeComponent(message);
    final deepLink = Uri.parse("whatsapp://send?phone=$formattedPhone&text=$encodedMsg");
    final fallbackWeb = Uri.parse("https://wa.me/$formattedPhone?text=$encodedMsg");

    try {
      if (await canLaunchUrl(deepLink)) {
        await launchUrl(deepLink, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(fallbackWeb)) {
        await launchUrl(fallbackWeb, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("WhatsApp is not installed on this device."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not open WhatsApp: $e")),
        );
      }
    }
  }
}

class PdfReceiptService {
  static Future<void> generateAndShareReceipt({
    required BuildContext context,
    required String studentName,
    required String parentName,
    required String batchName,
    required String monthYear,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMode,
    required String receiptNumber,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blueGrey700, width: 2),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "TUITIONMATE ACADEMY",
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.Text(
                          "Personalized Coaching & Mentorship",
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("FEES RECEIPT", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text("Rec #: $receiptNumber", style: const pw.TextStyle(fontSize: 10)),
                        pw.Text("Date: ${DateFormat('dd-MMM-yyyy').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey400, height: 20),
                pw.SizedBox(height: 8),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Student Name: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(studentName),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Parent/Guardian: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(parentName),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Batch/Class: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(batchName),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Billing Period: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(monthYear),
                  ],
                ),
                pw.SizedBox(height: 12),

                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  color: PdfColors.grey200,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Payment Mode:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(paymentMode.toUpperCase()),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  color: PdfColors.green50,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Amount Paid:", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      pw.Text("INR ${amountPaid.toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Remaining Due Balance:", style: pw.TextStyle(color: remainingBalance > 0 ? PdfColors.red : PdfColors.black)),
                    pw.Text("INR ${remainingBalance.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: remainingBalance > 0 ? PdfColors.red : PdfColors.black)),
                  ],
                ),
                pw.Spacer(),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Thank you for choosing TuitionMate!", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 80, height: 1, color: PdfColors.grey800),
                        pw.SizedBox(height: 3),
                        pw.Text("Tutor Signature", style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // Instant Share PDF to WhatsApp or Print dialog
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Receipt_${receiptNumber}_$studentName.pdf',
    );
  }
}

// ============================================================================
// 4. REPOSITORY & APP STATE CONTROLLER
// ============================================================================

class TuitionMateController extends ChangeNotifier {
  final dbHelper = DatabaseHelper.instance;

  List<Batch> batches = [];
  Batch? selectedBatch;

  List<Student> studentsInBatch = [];
  Map<int, AttendanceStatus> todayAttendance = {};
  List<FeeRecord> feeRecords = [];
  List<Inquiry> inquiries = [];

  bool isLoading = false;
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  TuitionMateController() {
    init();
  }

  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    await loadBatches();
    if (batches.isNotEmpty) {
      selectedBatch = batches.first;
      await loadBatchDetails(selectedBatch!.id!);
    }
    await loadInquiries();

    isLoading = false;
    notifyListeners();
  }

  Future<void> loadBatches() async {
    final db = await dbHelper.database;
    final res = await db.query('batches');
    batches = res.map((m) => Batch.fromMap(m)).toList();
    notifyListeners();
  }

  Future<void> selectBatch(Batch batch) async {
    selectedBatch = batch;
    await loadBatchDetails(batch.id!);
  }

  Future<void> loadBatchDetails(int batchId) async {
    final db = await dbHelper.database;

    // Load active students in batch
    final sRes = await db.query(
      'students',
      where: 'batch_id = ? AND status != ?',
      whereArgs: [batchId, 'left'],
    );
    studentsInBatch = sRes.map((m) => Student.fromMap(m)).toList();

    // Load attendance for current selected date
    final attRes = await db.query(
      'attendance',
      where: 'batch_id = ? AND date = ?',
      whereArgs: [batchId, selectedDate],
    );
    todayAttendance = {
      for (var row in attRes)
        row['student_id'] as int: AttendanceStatus.values.firstWhere(
          (e) => e.name == row['status'],
          orElse: () => AttendanceStatus.present,
        )
    };

    // Load Fees for this batch
    final feeRes = await db.query(
      'fee_records',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'due_date DESC',
    );
    feeRecords = feeRes.map((m) => FeeRecord.fromMap(m)).toList();

    notifyListeners();
  }

  Future<void> setAttendance(int studentId, AttendanceStatus status) async {
    if (selectedBatch == null) return;
    final db = await dbHelper.database;

    await db.insert(
      'attendance',
      {
        'student_id': studentId,
        'batch_id': selectedBatch!.id,
        'date': selectedDate,
        'status': status.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    todayAttendance[studentId] = status;
    notifyListeners();
  }

  Future<void> markAllPresent() async {
    if (selectedBatch == null) return;
    final db = await dbHelper.database;
    final batch = db.batch();

    for (var s in studentsInBatch) {
      todayAttendance[s.id!] = AttendanceStatus.present;
      batch.insert(
        'attendance',
        {
          'student_id': s.id,
          'batch_id': selectedBatch!.id,
          'date': selectedDate,
          'status': AttendanceStatus.present.name,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  Future<void> recordPayment({
    required BuildContext context,
    required FeeRecord feeRecord,
    required double payingAmount,
    required PaymentMode mode,
    required Student student,
  }) async {
    final db = await dbHelper.database;
    final newPaid = feeRecord.amountPaid + payingAmount;
    final newDue = (feeRecord.totalDue - newPaid).clamp(0.0, double.infinity);
    final newStatus = newDue <= 0.0 ? FeeStatus.paid : FeeStatus.partial;
    final receiptNum = "TM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

    await db.transaction((txn) async {
      // 1. Update fee record
      await txn.update(
        'fee_records',
        {
          'amount_paid': newPaid,
          'due_balance': newDue,
          'status': newStatus.name,
        },
        where: 'id = ?',
        whereArgs: [feeRecord.id],
      );

      // 2. Insert transaction entry
      await txn.insert('fee_transactions', {
        'fee_record_id': feeRecord.id,
        'amount': payingAmount,
        'payment_mode': mode.name,
        'transaction_date': DateTime.now().toIso8601String(),
        'receipt_number': receiptNum,
      });
    });

    if (selectedBatch != null) {
      await loadBatchDetails(selectedBatch!.id!);
    }

    // Auto-prompt instant PDF receipt generation
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment of ₹${payingAmount.toStringAsFixed(0)} logged! Receipt $receiptNum generated."),
          action: SnackBarAction(
            label: "Share Receipt",
            textColor: Colors.amberAccent,
            onPressed: () {
              PdfReceiptService.generateAndShareReceipt(
                context: context,
                studentName: student.name,
                parentName: student.parentName,
                batchName: selectedBatch?.name ?? "Tuition",
                monthYear: feeRecord.monthYear,
                amountPaid: payingAmount,
                remainingBalance: newDue,
                paymentMode: mode.name,
                receiptNumber: receiptNum,
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> loadInquiries() async {
    final db = await dbHelper.database;
    final res = await db.query('inquiries', orderBy: 'id DESC');
    inquiries = res.map((m) => Inquiry.fromMap(m)).toList();
    notifyListeners();
  }

  Future<void> addInquiry(Inquiry inquiry) async {
    final db = await dbHelper.database;
    await db.insert('inquiries', inquiry.toMap());
    await loadInquiries();
  }

  Future<void> updateInquiryStatus(int id, InquiryStatus newStatus) async {
    final db = await dbHelper.database;
    await db.update('inquiries', {'status': newStatus.name}, where: 'id = ?', whereArgs: [id]);
    await loadInquiries();
  }

  Future<void> createStudent(Student student) async {
    final db = await dbHelper.database;
    await db.insert('students', student.toMap());
    if (selectedBatch != null) {
      await loadBatchDetails(selectedBatch!.id!);
    }
  }
}

// ============================================================================
// 5. USER INTERFACE (MATERIAL 3 DESIGN)
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuitionMateApp());
}

class TuitionMateApp extends StatelessWidget {
  const TuitionMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TuitionMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Indigo Navy tailored for Indian educators
          brightness: Brightness.light,
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFF0D9488),
        ),
        cardTheme: CardTheme(
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  final TuitionMateController controller = TuitionMateController();
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = [
      AttendanceModuleView(controller: controller),
      FeesOverdueModuleView(controller: controller),
      InquiriesCrmView(controller: controller),
      TestsAndMarksView(controller: controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TuitionMate',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (controller.selectedBatch != null)
              Text(
                '${controller.selectedBatch!.timing} • ₹${controller.selectedBatch!.feeAmount.toInt()}/mo',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          // Top Batch Switcher Dropdown
          if (controller.batches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Batch>(
                  dropdownColor: const Color(0xFF1E3A8A),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  value: controller.selectedBatch,
                  items: controller.batches.map((b) {
                    return DropdownMenuItem<Batch>(
                      value: b,
                      child: Text(
                        b.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (Batch? newBatch) {
                    if (newBatch != null) {
                      controller.selectBatch(newBatch);
                    }
                  },
                ),
              ),
            ),
        ],
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: pages[_currentNavIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentNavIndex,
        onDestinationSelected: (idx) => setState(() => _currentNavIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Fees & Dues',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search),
            label: 'Inquiries',
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment),
            label: 'Tests',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODULE 1: SMART ATTENDANCE WITH 1-TAP WHATSAPP ABSENT DISPATCH
// ============================================================================

class AttendanceModuleView extends StatelessWidget {
  final TuitionMateController controller;
  const AttendanceModuleView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final batch = controller.selectedBatch;
    if (batch == null) {
      return const Center(child: Text("No batches available. Create a batch first."));
    }

    final totalStudents = controller.studentsInBatch.length;
    final presentCount = controller.todayAttendance.values.where((v) => v == AttendanceStatus.present).length;
    final absentCount = controller.todayAttendance.values.where((v) => v == AttendanceStatus.absent).length;
    final attendancePercent = totalStudents == 0 ? 0 : ((presentCount / totalStudents) * 100).toInt();

    return Column(
      children: [
        // Quick Metrics Dashboard Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricCard("Students", "$totalStudents", Icons.group, Colors.blueGrey),
              _buildMetricCard("Present", "$presentCount", Icons.check_circle, Colors.green),
              _buildMetricCard("Absent", "$absentCount", Icons.cancel, Colors.redAccent),
              _buildMetricCard("Turnout", "$attendancePercent%", Icons.pie_chart, Colors.indigo),
            ],
          ),
        ),

        // Action Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Date: ${controller.selectedDate}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => controller.markAllPresent(),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text("All Present"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: "Class Holiday / Broadcast",
                    icon: const Icon(Icons.campaign, color: Colors.deepOrange),
                    onPressed: () => _showBroadcastDialog(context),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Student Roll Call List
        Expanded(
          child: controller.studentsInBatch.isEmpty
              ? const Center(child: Text("No students enrolled in this batch."))
              : ListView.builder(
                  itemCount: controller.studentsInBatch.length,
                  itemBuilder: (context, index) {
                    final student = controller.studentsInBatch[index];
                    final status = controller.todayAttendance[student.id];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              child: Text(
                                student.name[0],
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    "P: ${student.parentName} (${student.parentPhone})",
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),

                            // Attendance Status Quick Buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _statusToggle(
                                  label: "P",
                                  isSelected: status == AttendanceStatus.present,
                                  color: Colors.green,
                                  onTap: () => controller.setAttendance(student.id!, AttendanceStatus.present),
                                ),
                                const SizedBox(width: 6),
                                _statusToggle(
                                  label: "L",
                                  isSelected: status == AttendanceStatus.late,
                                  color: Colors.amber.shade800,
                                  onTap: () => controller.setAttendance(student.id!, AttendanceStatus.late),
                                ),
                                const SizedBox(width: 6),
                                _statusToggle(
                                  label: "A",
                                  isSelected: status == AttendanceStatus.absent,
                                  color: Colors.red,
                                  onTap: () {
                                    controller.setAttendance(student.id!, AttendanceStatus.absent);
                                    _promptInstantAbsentWhatsApp(context, student);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String val, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _statusToggle({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: isSelected ? 1.5 : 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  void _promptInstantAbsentWhatsApp(BuildContext context, Student student) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("${student.name} marked Absent. Send WhatsApp alert?"),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: "Send WhatsApp",
          textColor: Colors.greenAccent,
          onPressed: () {
            WhatsAppService.sendAbsentAlert(
              context: context,
              parentPhone: student.parentPhone,
              parentName: student.parentName,
              studentName: student.name,
              batchName: controller.selectedBatch?.name ?? "Tuition Class",
            );
          },
        ),
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Batch Broadcast Announcement"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Send class cancellation, holiday, or timing changes to all parents in this batch.",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "e.g., Kal tuition class sham 6:00 baje shuru hogi.",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text("Send First via WA"),
            onPressed: () {
              if (noteController.text.trim().isNotEmpty && controller.studentsInBatch.isNotEmpty) {
                final firstStudent = controller.studentsInBatch.first;
                WhatsAppService.sendBroadcast(
                  context: context,
                  phone: firstStudent.parentPhone,
                  announcement: noteController.text.trim(),
                  batchName: controller.selectedBatch?.name ?? "Tuition",
                );
                Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODULE 2: FEES, OVERDUE BUCKETS & PARTIAL PAYMENTS
// ============================================================================

class FeesOverdueModuleView extends StatefulWidget {
  final TuitionMateController controller;
  const FeesOverdueModuleView({super.key, required this.controller});

  @override
  State<FeesOverdueModuleView> createState() => _FeesOverdueModuleViewState();
}

class _FeesOverdueModuleViewState extends State<FeesOverdueModuleView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.controller.feeRecords;
    final now = DateTime.now();

    // Grouping records into Indian tutor overdue buckets
    final upcoming = <FeeRecord>[];
    final overdue1To7 = <FeeRecord>[];
    final overdue8To15 = <FeeRecord>[];
    final overdue15Plus = <FeeRecord>[];

    for (var r in records) {
      if (r.dueBalance <= 0) continue; // Skip fully settled
      final dueDate = DateTime.tryParse(r.dueDate) ?? now;
      final diffDays = now.difference(dueDate).inDays;

      if (diffDays < 0 && diffDays >= -3) {
        upcoming.add(r);
      } else if (diffDays >= 0 && diffDays <= 7) {
        overdue1To7.add(r);
      } else if (diffDays >= 8 && diffDays <= 15) {
        overdue8To15.add(r);
      } else if (diffDays > 15) {
        overdue15Plus.add(r);
      } else {
        upcoming.add(r);
      }
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.black54,
          indicatorWeight: 3,
          tabs: [
            Tab(text: "Upcoming (${upcoming.length})"),
            Tab(text: "1-7 Days (${overdue1To7.length})"),
            Tab(text: "8-15 Days (${overdue8To15.length})"),
            Tab(text: "15+ Days (${overdue15Plus.length})"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBucketList(upcoming, "Upcoming Fees (Due Soon)"),
              _buildBucketList(overdue1To7, "Recent Overdue (1-7 Days)"),
              _buildBucketList(overdue8To15, "Attention Required (8-15 Days)"),
              _buildBucketList(overdue15Plus, "Critical Overdue (15+ Days)"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBucketList(List<FeeRecord> bucket, String emptyLabel) {
    if (bucket.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            const SizedBox(height: 8),
            Text("No records in $emptyLabel", style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: bucket.length,
      itemBuilder: (context, idx) {
        final fee = bucket[idx];
        final student = widget.controller.studentsInBatch.firstWhere(
          (s) => s.id == fee.studentId,
          orElse: () => Student(
            batchId: fee.batchId,
            name: "Student #${fee.studentId}",
            parentName: "Parent",
            parentPhone: "+919876543210",
            joiningDate: "",
          ),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      student.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: fee.status == FeeStatus.partial ? Colors.amber.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        fee.status == FeeStatus.partial ? "PARTIAL" : "UNPAID",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: fee.status == FeeStatus.partial ? Colors.amber.shade900 : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total: ₹${fee.totalDue.toInt()}", style: const TextStyle(color: Colors.black54)),
                    Text("Paid: ₹${fee.amountPaid.toInt()}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                    Text("Balance: ₹${fee.dueBalance.toInt()}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Due Date: ${fee.dueDate} (${fee.monthYear})", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 1-Tap WhatsApp Reminder with UPI ID
                    OutlinedButton.icon(
                      icon: const Icon(Icons.send_to_mobile, size: 16, color: Colors.green),
                      label: const Text("WhatsApp Reminder", style: TextStyle(color: Colors.green)),
                      onPressed: () {
                        WhatsAppService.sendFeeReminder(
                          context: context,
                          parentPhone: student.parentPhone,
                          parentName: student.parentName,
                          studentName: student.name,
                          dueBalance: fee.dueBalance,
                          dueDate: fee.dueDate,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Log Payment (Part/Full)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.payment, size: 16),
                      label: const Text("Pay"),
                      onPressed: () => _showPaymentSheet(context, fee, student),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPaymentSheet(BuildContext context, FeeRecord fee, Student student) {
    final amountController = TextEditingController(text: fee.dueBalance.toStringAsFixed(0));
    PaymentMode selectedMode = PaymentMode.upi;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Record Fee Payment: ${student.name}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                "Current Due Balance: ₹${fee.dueBalance.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Paying Amount (₹)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 14),
              const Text("Payment Mode:", style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: PaymentMode.values.map((mode) {
                  return ChoiceChip(
                    label: Text(mode.name.toUpperCase()),
                    selected: selectedMode == mode,
                    onSelected: (val) {
                      if (val) setSheetState(() => selectedMode = mode);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("Confirm & Auto-Generate Receipt"),
                  onPressed: () {
                    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
                    if (amount <= 0) return;
                    Navigator.pop(ctx);
                    widget.controller.recordPayment(
                      context: context,
                      feeRecord: fee,
                      payingAmount: amount,
                      mode: selectedMode,
                      student: student,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MODULE 3: MINI CRM & INQUIRY PIPELINE
// ============================================================================

class InquiriesCrmView extends StatelessWidget {
  final TuitionMateController controller;
  const InquiriesCrmView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final inquiries = controller.inquiries;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text("New Inquiry"),
        onPressed: () => _showAddInquiryDialog(context),
      ),
      body: inquiries.isEmpty
          ? const Center(child: Text("No inquiries yet. Log your student admission leads here."))
          : ListView.builder(
              padding: const EdgeInsets.only(left: 14, right: 14, top: 12, bottom: 80),
              itemCount: inquiries.length,
              itemBuilder: (context, idx) {
                final inq = inquiries[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              inq.studentName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            _buildStatusTag(inq.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Phone: ${inq.parentPhone} • Subject: ${inq.gradeSubject}",
                          style: const TextStyle(color: Colors.black87, fontSize: 13),
                        ),
                        if (inq.notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text("Notes: ${inq.notes}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1-Tap WhatsApp Follow-up
                            IconButton.outlined(
                              icon: const Icon(Icons.chat, color: Colors.green),
                              tooltip: "Send WhatsApp Follow-up",
                              onPressed: () {
                                final msg = "Namaste Ji,\n"
                                    "Tuition admission inquiry ke baare me follow-up tha regarding ${inq.studentName} for ${inq.gradeSubject}. "
                                    "Aap demo class kab schedule karna chahenge?\n\n- ${WhatsAppService.defaultTutorName}";
                                WhatsAppService.openWhatsApp(
                                  phone: inq.parentPhone,
                                  message: msg,
                                  context: context,
                                );
                              },
                            ),

                            // Pipeline Stage Selector
                            DropdownButton<InquiryStatus>(
                              value: inq.status,
                              underline: const SizedBox(),
                              items: InquiryStatus.values.map((s) {
                                return DropdownMenuItem(
                                  value: s,
                                  child: Text(_formatStatus(s), style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (newStatus) {
                                if (newStatus != null) {
                                  controller.updateInquiryStatus(inq.id!, newStatus);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusTag(InquiryStatus status) {
    Color color;
    switch (status) {
      case InquiryStatus.newInquiry:
        color = Colors.blue;
        break;
      case InquiryStatus.demoScheduled:
        color = Colors.orange;
        break;
      case InquiryStatus.joined:
        color = Colors.green;
        break;
      case InquiryStatus.closed:
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  String _formatStatus(InquiryStatus s) {
    switch (s) {
      case InquiryStatus.newInquiry:
        return "New Inquiry";
      case InquiryStatus.demoScheduled:
        return "Demo Scheduled";
      case InquiryStatus.joined:
        return "Converted / Joined";
      case InquiryStatus.closed:
        return "Closed";
    }
  }

  void _showAddInquiryDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("New Student Inquiry"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Student Name")),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Parent Phone (+91...)"), keyboardType: TextInputType.phone),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: "Class / Subject")),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: "Notes / Specific Needs")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                controller.addInquiry(
                  Inquiry(
                    studentName: nameCtrl.text.trim(),
                    parentPhone: phoneCtrl.text.trim(),
                    gradeSubject: subjectCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                  ),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save Lead"),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODULE 4: TESTS, MARKS & REPORT CARDS
// ============================================================================

class TestsAndMarksView extends StatelessWidget {
  final TuitionMateController controller;
  const TestsAndMarksView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Recent Weekly Test: Chapter 4 Quadratic Equations",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text("Max Marks: 40 • Date: 20 Sep 2026", style: TextStyle(color: Colors.black54)),
                const Divider(height: 20),
                _buildStudentScoreRow(
                  context: context,
                  studentName: "Aarav Sharma",
                  parentPhone: "+919876543210",
                  marks: 38.0,
                  total: 40.0,
                  rank: "1st",
                  remarks: "Excellent grasp of word problems.",
                ),
                const SizedBox(height: 10),
                _buildStudentScoreRow(
                  context: context,
                  studentName: "Diya Patel",
                  parentPhone: "+919811223344",
                  marks: 29.5,
                  total: 40.0,
                  rank: "2nd",
                  remarks: "Good effort. Review factoring formulas.",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentScoreRow({
    required BuildContext context,
    required String studentName,
    required String parentPhone,
    required double marks,
    required double total,
    required String rank,
    required String remarks,
  }) {
    final percent = ((marks / total) * 100).toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text("Score: $marks / $total ($percent%) • Rank: $rank", style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.green),
          tooltip: "Share Report Card to Parent",
          onPressed: () {
            final msg = "📊 *Tuition Progress Card*\n\n"
                "Student: $studentName\n"
                "Test: Quadratic Equations\n"
                "Marks: $marks / $total ($percent%)\n"
                "Batch Rank: $rank\n"
                "Remark: $remarks\n\n"
                "- ${WhatsAppService.defaultTutorName}";

            WhatsAppService.openWhatsApp(
              phone: parentPhone,
              message: msg,
              context: context,
            );
          },
        ),
      ],
    );
  }
}
