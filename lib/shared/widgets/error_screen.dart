import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

class ErrorScreen extends StatelessWidget {
  final String title;
  final String message;
  final String? technicalDetails;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  const ErrorScreen({
    super.key,
    this.title = 'Oops! Something went wrong',
    required this.message,
    this.technicalDetails,
    this.onRetry,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(AppTokens.spacing32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radius14),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.overlay,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(AppTokens.spacing20),
                decoration: BoxDecoration(
                  color: AppColors.danger.tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.alertTriangle,
                  size: 48,
                  color: AppColors.danger.dark,
                ),
              ),
              const SizedBox(height: AppTokens.spacing24),
              
              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textStrong,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTokens.spacing12),
              
              // Friendly Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textBody,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              // Technical details (Inline message for understanding)
              if (technicalDetails != null) ...[
                const SizedBox(height: AppTokens.spacing24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTokens.spacing16),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(AppTokens.radius10),
                    border: Border.all(color: AppColors.danger.tint),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Technical Details:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spacing8),
                      Text(
                        technicalDetails!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.danger.base,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: AppTokens.spacing32),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onBack != null)
                    OutlinedButton.icon(
                      onPressed: onBack,
                      icon: const Icon(LucideIcons.arrowLeft, size: 16),
                      label: const Text('Go Back'),
                    ),
                  if (onBack != null && onRetry != null)
                    const SizedBox(width: AppTokens.spacing16),
                  if (onRetry != null)
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                      ),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Try Again'),
                    ),
                  
                  // Default back button if neither provided but we can pop
                  if (onBack == null && onRetry == null && Navigator.canPop(context))
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.arrowLeft, size: 16),
                      label: const Text('Return to Safety'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
