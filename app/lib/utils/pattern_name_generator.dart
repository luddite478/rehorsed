/// Utility for generating default pattern names
class PatternNameGenerator {
  /// Generate a default name for a pattern based on current date/time
  /// Format: "Pattern - Oct 5, 2025"
  static String generate() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    
    return 'Pattern - ${months[now.month - 1]} ${now.day}, ${now.year}';
  }
  
  /// Generate a name with a custom prefix
  /// Format: "My Pattern - Oct 5, 2025"
  static String generateWithPrefix(String prefix) {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    
    return '$prefix - ${months[now.month - 1]} ${now.day}, ${now.year}';
  }
  
  /// Generate a simple timestamped name
  /// Format: "20251005_143022"
  static String generateTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
           '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
}
