import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme_helpers.dart';
import 'contact_page.dart';

class HelpCenterPage extends StatelessWidget {
  final bool isDarkTheme;

  const HelpCenterPage({Key? key, required this.isDarkTheme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(isDarkTheme);
    
    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: AppBar(
        backgroundColor: themeColors.mainBackgroundColor,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Centro Assistenza',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: themeColors.iconColor, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        toolbarHeight: 80,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_center, color: Colors.blue, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Domande Frequenti',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Trova rapidamente le risposte alle domande più comuni su SaveIn!.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24),
            
            ...(AppConstants.faqItems.map((faq) => _buildFAQItem(faq, Colors.white, Colors.black87, Colors.black54)).toList()),
            
            SizedBox(height: 32),
            
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Icon(Icons.contact_support, color: Colors.blue, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'Non hai trovato quello che cercavi?',
                    style: TextStyle(
                      color: themeColors.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Contattaci per ricevere assistenza personalizzata',
                    style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ContactPage(isDarkTheme: isDarkTheme),
                        ),
                      );
                    },
                    icon: Icon(Icons.send, size: 18),
                    label: Text('Contattaci'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 32),
          ],
        ),
      ),
      
      bottomNavigationBar: SafeArea(
        child: Container(
          color: themeColors.bottomBarColor,
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                icon: Icon(Icons.home, color: themeColors.iconColor, size: 28),
              ),
              FloatingActionButton(
                onPressed: () => _showCreateFolderDialog(context),
                backgroundColor: Colors.white,
                heroTag: "fab_help_center",
                child: Icon(Icons.add, color: Colors.black, size: 28),
                mini: false,
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.person, color: themeColors.iconColor, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAQItem(FAQItem faq, Color? cardColor, Color textColor, Color subtitleColor) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Text(
          faq.question,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        iconColor: textColor,
        collapsedIconColor: subtitleColor,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              faq.answer,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova Cartella',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Torna alla home per creare una nuova cartella',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(color: Colors.black87),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
                

              }
            },
            child: Text('Vai alla Home'),
          ),
        ],
      ),
    );
  }
}