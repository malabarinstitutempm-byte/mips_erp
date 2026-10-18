// src/lib/pdfExporter.ts
// Lazy-loaded PDF generator using html2pdf.js

export async function exportElementToPdf(
  element: HTMLElement,
  filename: string,
  options?: {
    orientation?: 'portrait' | 'landscape';
    margin?: number[];
  }
): Promise<void> {
  // Dynamically import html2pdf to prevent bundling heavy PDF libraries upfront
  const html2pdfModule = await import('html2pdf.js');
  const html2pdf = (html2pdfModule as any).default || html2pdfModule;

  const opt = {
    margin: options?.margin || [10, 12, 10, 12],
    filename: filename.endsWith('.pdf') ? filename : `${filename}.pdf`,
    image: { type: 'jpeg', quality: 0.98 },
    html2canvas: {
      scale: 2,
      useCORS: true,
      letterRendering: true,
      logging: false,
    },
    jsPDF: {
      unit: 'mm',
      format: 'a4',
      orientation: options?.orientation || 'portrait',
    },
    pagebreak: { mode: ['avoid-all', 'css', 'legacy'] },
  };

  await html2pdf().set(opt).from(element).save();
}
