/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        navy: {
          DEFAULT: '#0B2A4A',
          text: '#B7C7DD',
        },
        primary: {
          DEFAULT: '#1F5FBF',
          hover: '#174EA0',
          ring: '#BBD3F5',
        },
        teal: {
          DEFAULT: '#19B5A5',
          dark: '#0D7B70',
        },
        pageBg: '#F7F9FC',
        surface: '#F3F6FB',
        cardBorder: '#E1E8F2',
        muted: '#5B6B7F',
        inputBorder: '#C9D4E3',
        focusRing: '#BBD3F5',
        success: {
          bg: '#E3F6EC',
          border: '#BFE6D1',
          text: '#0B5D3B',
        },
        warning: {
          bg: '#FFF3D6',
          border: '#F1D9A0',
          text: '#7A4B00',
        },
        error: {
          bg: '#FDECEC',
          border: '#F3BDBD',
          text: '#8A1F1F',
          accent: '#C93A3A',
        },
      },
      fontFamily: {
        sora: ['Sora', 'sans-serif'],
        sans: ['"Plus Jakarta Sans"', 'sans-serif'],
      },
      boxShadow: {
        'card': '0 1px 3px rgba(11, 42, 74, 0.05)',
        'login-card': '0 16px 48px rgba(11, 42, 74, 0.09)',
        'primary-btn': '0 8px 20px rgba(31, 95, 191, 0.30)',
      },
      borderRadius: {
        'card': '20px',
        'card-lg': '24px',
        'input': '12px',
        'btn': '14px',
      },
      minHeight: {
        'touch': '44px',
      },
      minWidth: {
        'touch': '44px',
      },
    },
  },
  plugins: [],
}
