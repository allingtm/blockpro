# APP_TEMPLATE.md — Flutter + Bubble API App Template

> **Purpose:** Generic template for an AI assistant to scaffold any new Flutter app backed by a Bubble.io REST API.
> Covers: auth (email/password login via Bubble API), sidebar drawer, bottom nav bar, profile/account settings, and a full theme system.
> Does NOT include domain-specific features — add your own screens/models on top.

| Attribute | Value |
|-----------|-------|
| **Framework** | Flutter 3.5+ / Dart |
| **Backend** | Bubble.io (custom REST API) |
| **State Management** | Riverpod |
| **Routing** | GoRouter with auth redirects |
| **Theme** | Material 3 via FlexColorScheme + ThemeExtension (tokens) |
| **Auth** | Email + password via Bubble API, Bearer token, SharedPreferences persistence |

---

## 1. Project Blueprint

### 1a. Directory Structure

```
lib/
├── core/
│   ├── config/api_config.dart         # Loads .env credentials (Bubble base URL)
│   └── router/app_router.dart         # All routes + auth redirects
├── models/
│   ├── user_struct.dart               # API login response model
│   ├── response_struct.dart           # Nested auth response (token, userId, expires)
│   └── user_profile.dart              # User profile model (if needed beyond auth)
├── providers/
│   ├── auth_provider.dart             # Auth state chain
│   ├── theme_provider.dart            # Theme + brightness persistence
│   └── user_profile_provider.dart     # Profile state
├── repositories/
│   ├── auth_repository.dart           # Auth data access (login, logout, token mgmt)
│   └── api_repository.dart            # Protected API calls to Bubble
├── screens/
│   ├── auth/
│   │   └── login_screen.dart          # Email + password login
│   ├── home_screen.dart               # Bottom nav + drawer
│   ├── profile_screen.dart            # View profile
│   ├── settings_screen.dart           # Theme, account, about
│   └── welcome_screen.dart            # Unauthenticated landing
├── theme/
│   ├── app_palettes.dart              # ThemeVariant enum + FlexSchemeData definitions
│   ├── app_theme.dart                 # FlexThemeData wrapper + extensions
│   ├── app_theme_tokens.dart          # Spacing/radius/icon tokens (ThemeExtension)
│   └── app_typography.dart            # Text style constants
├── utils/
│   ├── error_utils.dart               # User-friendly error messages
│   └── string_utils.dart              # Input sanitisation (escapeStringForJson)
└── widgets/
    └── common/
        ├── app_button.dart            # Primary/outline/ghost button
        ├── app_text_field.dart        # Text field with factory constructors
        ├── app_card.dart              # Themed card wrapper
        └── widgets.dart               # Barrel export
```

### 1b. Conventions

- **Barrel files:** Each widget folder has a barrel file re-exporting all public widgets.
- **Environment:** `.env` file (git-ignored) with `BUBBLE_API_BASE_URL`. Template at `.env.example`.
- **Naming:** `snake_case` files, `PascalCase` classes, `camelCase` members.
- **Immutable models:** All model classes use `final` fields + `copyWith()`.

---

## 2. Architecture (4-Layer)

```
┌─────────────────────────────────────────────────────────────┐
│                      UI Layer (Screens)                      │
│             screens/auth/    screens/home_screen             │
├─────────────────────────────────────────────────────────────┤
│                   State Layer (Riverpod)                     │
│       auth_provider    theme_provider    user_profile_provider│
├─────────────────────────────────────────────────────────────┤
│                 Repository Layer (Data Access)               │
│              auth_repository    api_repository               │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer (Bubble API)                   │
│               REST API + Bearer Token Auth                   │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow Example: Login

```
LoginScreen
  → calls ref.read(authRepositoryProvider).login(email, password)
    → AuthRepository sends POST to /applogin
      → Bubble returns { status, response: { token, userId, expires } }
        → AuthRepository stores token + expiry in SharedPreferences
          → authStateProvider emits AuthState(loggedIn: true)
            → isAuthenticatedProvider = true
              → GoRouter redirect → /home
```

### Right vs Wrong

```dart
// RIGHT: Screen → Provider → Repository → Bubble API
class LoginScreen extends ConsumerWidget {
  Widget build(context, ref) {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.login(email: email, password: password);
  }
}

// WRONG: Direct HTTP calls in UI
class LoginScreen extends StatelessWidget {
  Widget build(context) {
    await http.post(Uri.parse('$baseUrl/applogin'), ...); // Never!
  }
}
```

---

## 3. Entry Point (main.dart)

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await dotenv.load(fileName: '.env');

  // Initialize auth — loads persisted token from SharedPreferences
  final container = ProviderContainer();
  await container.read(authRepositoryProvider).initialize();

  // TODO: Initialize additional services here (push notifications, analytics, etc.)

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MainApp(),
    ),
  );
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final themeMode = ref.watch(brightnessModeProvider);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        ),
      ),
      child: MaterialApp.router(
        title: 'MyApp',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOut,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
```

**Key decisions:**
- **Auth initialization before runApp** — loads persisted token from SharedPreferences on startup, checks expiry, and sets initial auth state.
- **UncontrolledProviderScope** — uses a pre-created `ProviderContainer` so the auth repository can be initialized before the widget tree builds.
- **Text scale clamping** — prevents layout breakage on accessibility settings (0.85×–1.3×).
- **Theme animation** — smooth 300ms transition when switching palettes.
- **Light + dark themes** — both passed to `MaterialApp.router`; `themeMode` controls which is active (system/light/dark).
- **No third-party SDK initialization** — all backend communication is via plain HTTP to the Bubble API.

---

## 4. Theme System

The theme system uses [FlexColorScheme](https://pub.dev/packages/flex_color_scheme) (`^8.4.0`) — a Flutter Favourite package — to generate complete Material 3 `ThemeData` from seed colors. Custom spacing, radius, and icon tokens are layered on top via a `ThemeExtension`.

### Theme Flow

```
ThemeVariant enum (user picks)
  → AppPalettes.getSchemeData(variant) → FlexSchemeData (light + dark seed colors)
    → AppTheme.light() / .dark() → ThemeData
        ├── FlexThemeData.light() or .dark()
        │     ├── ColorScheme (M3 seed-generated tonal palettes)
        │     ├── Component themes (AppBar, Input, Card, etc. via FlexSubThemesData)
        │     └── Surface blends, tinted interactions
        └── extensions: [AppThemeTokens]
```

**Visual configuration:** Use the [Themes Playground](https://rydmike.com/flexcolorscheme/themesplayground-latest) web app to visually configure FlexColorScheme settings and copy the generated API code.

### 4a. Design Tokens — `AppThemeTokens`

A `ThemeExtension` providing spacing, radius, and icon size tokens. These are **not** colour-related and complement FlexColorScheme.

```dart
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    this.spacingXs = 4,
    this.spacingSm = 8,
    this.spacingMd = 12,
    this.spacingLg = 16,
    this.spacingXl = 24,
    this.spacing2xl = 32,
    this.spacing3xl = 40,
    this.spacing4xl = 60,
    this.radiusSm = 4,
    this.radiusMd = 8,
    this.radiusLg = 12,
    this.radiusXl = 16,
    this.iconSm = 20,
    this.iconMd = 35,
    this.iconLg = 48,
    this.iconXl = 80,
    this.icon2xl = 100,
  });

  final double spacingXs, spacingSm, spacingMd, spacingLg;
  final double spacingXl, spacing2xl, spacing3xl, spacing4xl;
  final double radiusSm, radiusMd, radiusLg, radiusXl;
  final double iconSm, iconMd, iconLg, iconXl, icon2xl;

  static const standard = AppThemeTokens();

  @override
  AppThemeTokens copyWith({ /* all fields */ }) { /* ... */ }

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    // lerpDouble each field for smooth theme transitions
  }
}
```

**Token Scale Reference:**

| Token | Value | Usage |
|-------|-------|-------|
| `spacingXs` | 4 | Tight gaps (icon-to-text) |
| `spacingSm` | 8 | Small gaps (list item padding) |
| `spacingMd` | 12 | Default padding (cards, inputs) |
| `spacingLg` | 16 | Section spacing |
| `spacingXl` | 24 | Large gaps |
| `spacing2xl` | 32 | Page margins |
| `spacing3xl` | 40 | Hero spacing |
| `spacing4xl` | 60 | Splash/onboarding |
| `radiusSm` | 4 | Subtle rounding (chips) |
| `radiusMd` | 8 | Cards |
| `radiusLg` | 12 | Buttons, inputs |
| `radiusXl` | 16 | Modals, bottom sheets |
| `iconSm` | 20 | Inline icons |
| `iconMd` | 35 | Button icons |
| `iconLg` | 48 | Feature icons |
| `iconXl` | 80 | Empty state illustrations |
| `icon2xl` | 100 | Splash/onboarding icons |

**Access pattern:**
```dart
// RIGHT: Use context.tokens extension
final tokens = context.tokens;
Padding(padding: EdgeInsets.all(tokens.spacingMd));
BorderRadius.circular(tokens.radiusLg);

// WRONG: Magic numbers
Padding(padding: EdgeInsets.all(12));   // What does 12 mean?
BorderRadius.circular(16);              // Inconsistent
```

The `context.tokens` extension:
```dart
extension AppThemeTokensExtension on BuildContext {
  AppThemeTokens get tokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? const AppThemeTokens();
}
```

### 4b. Color Palette Variants — `AppPalettes`

Each variant defines 6 seed colours (primary, primaryContainer, secondary, secondaryContainer, tertiary, tertiaryContainer) for both light and dark modes. FlexColorScheme uses these seeds to generate a complete Material 3 `ColorScheme` with full tonal palettes.

```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Available theme variants the user can select.
enum ThemeVariant {
  forest('Forest'),
  ocean('Ocean'),
  rose('Rose'),
  ember('Ember'),
  midnight('Midnight'),
  lavender('Lavender'),
  highContrast('High Contrast');

  final String displayName;
  const ThemeVariant(this.displayName);
}

/// Defines seed color schemes for each ThemeVariant.
///
/// FlexColorScheme generates full M3 tonal palettes from these seeds.
/// Only 6 colours are needed per mode — the rest is computed.
class AppPalettes {
  AppPalettes._();

  // ── Forest ──────────────────────────────────────────────
  static const forest = FlexSchemeData(
    name: 'Forest',
    description: 'Natural greens with warm earth tones',
    light: FlexSchemeColor(
      primary: Color(0xFF4A7C59),
      primaryContainer: Color(0xFFB8E0C4),
      secondary: Color(0xFF8B6914),
      secondaryContainer: Color(0xFFFFF0C2),
      tertiary: Color(0xFF5C6B5E),
      tertiaryContainer: Color(0xFFD8E8DA),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFF81C784),
      primaryContainer: Color(0xFF2E5235),
      secondary: Color(0xFFFFD270),
      secondaryContainer: Color(0xFF5C4400),
      tertiary: Color(0xFFA8C4AA),
      tertiaryContainer: Color(0xFF3A4A3C),
    ),
  );

  // ── Ocean ───────────────────────────────────────────────
  static const ocean = FlexSchemeData(
    name: 'Ocean',
    description: 'Deep blues with coral accents',
    light: FlexSchemeColor(
      primary: Color(0xFF1565C0),
      primaryContainer: Color(0xFFD1E4FF),
      secondary: Color(0xFFE65100),
      secondaryContainer: Color(0xFFFFDBC8),
      tertiary: Color(0xFF006B5E),
      tertiaryContainer: Color(0xFFC2F0E9),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFF90CAF9),
      primaryContainer: Color(0xFF0D47A1),
      secondary: Color(0xFFFFAB6B),
      secondaryContainer: Color(0xFF7A3300),
      tertiary: Color(0xFF6FD5C5),
      tertiaryContainer: Color(0xFF004D42),
    ),
  );

  // ── Rose ────────────────────────────────────────────────
  static const rose = FlexSchemeData(
    name: 'Rose',
    description: 'Warm pinks with soft purples',
    light: FlexSchemeColor(
      primary: Color(0xFFC2185B),
      primaryContainer: Color(0xFFFFD9E2),
      secondary: Color(0xFF7B1FA2),
      secondaryContainer: Color(0xFFF3E5F5),
      tertiary: Color(0xFF8D6E63),
      tertiaryContainer: Color(0xFFEFDED8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFF48FB1),
      primaryContainer: Color(0xFF880E4F),
      secondary: Color(0xFFCE93D8),
      secondaryContainer: Color(0xFF4A148C),
      tertiary: Color(0xFFBCAAA4),
      tertiaryContainer: Color(0xFF4E342E),
    ),
  );

  // ── Ember ───────────────────────────────────────────────
  static const ember = FlexSchemeData(
    name: 'Ember',
    description: 'Bold orange with dark contrast',
    light: FlexSchemeColor(
      primary: Color(0xFFE65100),
      primaryContainer: Color(0xFFFFCCBC),
      secondary: Color(0xFF212121),
      secondaryContainer: Color(0xFFE0E0E0),
      tertiary: Color(0xFF795548),
      tertiaryContainer: Color(0xFFEFDED8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFFFAB6B),
      primaryContainer: Color(0xFF8B3200),
      secondary: Color(0xFFBDBDBD),
      secondaryContainer: Color(0xFF424242),
      tertiary: Color(0xFFBCAAA4),
      tertiaryContainer: Color(0xFF3E2723),
    ),
  );

  // ── Midnight ────────────────────────────────────────────
  static const midnight = FlexSchemeData(
    name: 'Midnight',
    description: 'Deep navy with gold accents',
    light: FlexSchemeColor(
      primary: Color(0xFF00296B),
      primaryContainer: Color(0xFFA0C2ED),
      secondary: Color(0xFFD26900),
      secondaryContainer: Color(0xFFFFD270),
      tertiary: Color(0xFF5C5C95),
      tertiaryContainer: Color(0xFFC8DBF8),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFB1CFF5),
      primaryContainer: Color(0xFF3873BA),
      secondary: Color(0xFFFFD270),
      secondaryContainer: Color(0xFFD26900),
      tertiary: Color(0xFFC9CBFC),
      tertiaryContainer: Color(0xFF535393),
    ),
  );

  // ── Lavender ────────────────────────────────────────────
  static const lavender = FlexSchemeData(
    name: 'Lavender',
    description: 'Soft purple with sage green',
    light: FlexSchemeColor(
      primary: Color(0xFF6750A4),
      primaryContainer: Color(0xFFE8DEF8),
      secondary: Color(0xFF558B2F),
      secondaryContainer: Color(0xFFDCEDC8),
      tertiary: Color(0xFF7D5260),
      tertiaryContainer: Color(0xFFFFD9E3),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFCFBCFF),
      primaryContainer: Color(0xFF4F378B),
      secondary: Color(0xFFC5E1A5),
      secondaryContainer: Color(0xFF33691E),
      tertiary: Color(0xFFEFB8C8),
      tertiaryContainer: Color(0xFF633B48),
    ),
  );

  // ── High Contrast ───────────────────────────────────────
  static const highContrast = FlexSchemeData(
    name: 'High Contrast',
    description: 'Maximum readability (WCAG AAA)',
    light: FlexSchemeColor(
      primary: Color(0xFF000000),
      primaryContainer: Color(0xFFE0E0E0),
      secondary: Color(0xFF00296B),
      secondaryContainer: Color(0xFFD1E4FF),
      tertiary: Color(0xFF4A148C),
      tertiaryContainer: Color(0xFFF3E5F5),
    ),
    dark: FlexSchemeColor(
      primary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF424242),
      secondary: Color(0xFF90CAF9),
      secondaryContainer: Color(0xFF0D47A1),
      tertiary: Color(0xFFCE93D8),
      tertiaryContainer: Color(0xFF4A148C),
    ),
  );

  /// Returns the FlexSchemeData for a given variant.
  static FlexSchemeData getSchemeData(ThemeVariant variant) {
    return switch (variant) {
      ThemeVariant.forest => forest,
      ThemeVariant.ocean => ocean,
      ThemeVariant.rose => rose,
      ThemeVariant.ember => ember,
      ThemeVariant.midnight => midnight,
      ThemeVariant.lavender => lavender,
      ThemeVariant.highContrast => highContrast,
    };
  }

  /// Returns [backgroundColor, primaryColor] for theme selector preview circles.
  static List<Color> getPreviewColors(ThemeVariant variant, Brightness brightness) {
    final data = getSchemeData(variant);
    final colors = brightness == Brightness.dark ? data.dark : data.light;
    return [
      brightness == Brightness.dark ? const Color(0xFF1C1B1F) : Colors.white,
      colors.primary,
    ];
  }
}
```

**Accessibility:** The `highContrast` variant uses black/white primaries and targets WCAG AAA (7:1). FlexColorScheme also provides `FlexTones.highContrast()` and `FlexTones.ultraContrast()` for even more accessible seed-generated palettes.

**Adding a new variant:** Define a new `FlexSchemeData` const with 6 light + 6 dark seed colours, add it to the enum, and add it to the `getSchemeData` switch. FlexColorScheme generates the remaining ~25 `ColorScheme` colours automatically.

### 4c. Theme Factory — `AppTheme`

Uses `FlexThemeData` to generate complete `ThemeData` objects. All component theming (AppBar, inputs, cards, buttons, chips, dialogs, etc.) is handled by `FlexSubThemesData` — no more manual `InputDecorationTheme`, `CardTheme`, etc.

```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'app_theme_tokens.dart';

/// Builds ThemeData using FlexColorScheme.
///
/// Uses the seed colours from [AppPalettes] to generate a complete
/// Material 3 ColorScheme with tonal palettes, surface blends,
/// and component themes.
class AppTheme {
  AppTheme._();

  /// Build a light theme from a [FlexSchemeData].
  static ThemeData light(FlexSchemeData schemeData) {
    return FlexThemeData.light(
      // ── Colours ─────────────────────────────────────
      colors: schemeData.light,
      useMaterial3: true,

      // ── Seed-generated ColorScheme ──────────────────
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),

      // ── Surface blending ────────────────────────────
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 4,

      // ── Component themes ────────────────────────────
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 10,
        blendOnColors: false,
        blendTextTheme: true,

        // Input decoration
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 12.0,
        inputDecoratorIsFilled: true,

        // Consistent radius (or omit for M3 per-widget defaults)
        defaultRadius: 12.0,

        // AppBar
        appBarCenterTitle: true,
        appBarScrolledUnderElevation: 0,
      ),

      // ── Typography ──────────────────────────────────
      typography: Typography.material2021(
        platform: TargetPlatform.android,
      ),

      // ── Theme extensions ────────────────────────────
      extensions: <ThemeExtension<dynamic>>{
        AppThemeTokens.standard,
      },
    );
  }

  /// Build a dark theme from a [FlexSchemeData].
  static ThemeData dark(FlexSchemeData schemeData) {
    return FlexThemeData.dark(
      colors: schemeData.dark,
      useMaterial3: true,

      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),

      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 8,

      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        tintedDisabledControls: true,
        blendOnLevel: 20,
        blendOnColors: true,
        blendTextTheme: true,

        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 12.0,
        inputDecoratorIsFilled: true,

        defaultRadius: 12.0,

        appBarCenterTitle: true,
        appBarScrolledUnderElevation: 0,
      ),

      typography: Typography.material2021(
        platform: TargetPlatform.android,
      ),

      extensions: <ThemeExtension<dynamic>>{
        AppThemeTokens.standard,
      },
    );
  }
}
```

**Key decisions:**
- **`FlexKeyColors` with secondary + tertiary** — uses all three seed colours to generate distinct tonal palettes (richer than `ColorScheme.fromSeed` which only uses primary).
- **`FlexSubThemesData`** — handles all component theming in one place. No more manual `InputDecorationTheme`, `CardTheme`, `AppBarTheme`, etc.
- **`defaultRadius: 12.0`** — consistent border radius on all components. Remove this to use M3 per-widget defaults instead.
- **Surface blending** — primary colour subtly tints surfaces for visual cohesion. `blendLevel` is higher in dark mode for better depth.
- **`AppThemeTokens` as extension** — spacing/radius/icon tokens are accessible via `context.tokens`.

### 4d. Typography — `AppTypography`

```dart
class AppTypography {
  AppTypography._();

  // Display
  static const TextStyle displayLarge = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.25,
  );

  // Headlines
  static const TextStyle headlineLarge = TextStyle(fontSize: 22, fontWeight: FontWeight.w600);
  static const TextStyle headlineMedium = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const TextStyle headlineSmall = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

  // Titles
  static const TextStyle titleLarge = TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
  static const TextStyle titleMedium = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
  static const TextStyle titleSmall = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);

  // Body
  static const TextStyle bodyLarge = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const TextStyle bodyLargeBold = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
  static const TextStyle bodyMedium = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const TextStyle bodySmall = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);

  // Labels
  static const TextStyle labelLarge = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const TextStyle labelMedium = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
  static const TextStyle labelSmall = TextStyle(fontSize: 11, fontWeight: FontWeight.w500);

  // Caption
  static const TextStyle caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
}
```

**Usage:**
```dart
// RIGHT: Use AppTypography constants
Text('Welcome', style: AppTypography.displayLarge);
Text('Subtitle', style: AppTypography.bodyMedium);

// ALSO RIGHT: Use the theme's TextTheme (populated by FlexColorScheme)
Text('Welcome', style: Theme.of(context).textTheme.headlineLarge);

// WRONG: Inline TextStyle
Text('Welcome', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold));
```

### 4e. Colour Access Patterns

FlexColorScheme generates a full Material 3 `ColorScheme`. Access it via `Theme.of(context).colorScheme` or the convenience extension (defined at the bottom of `app_theme.dart`):

```dart
/// Convenience extension for accessing ColorScheme from BuildContext.
extension AppColorsExtension on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}
```

**Usage:**
```dart
// RIGHT: Use context.colors (extension on ColorScheme)
final colors = context.colors;
Container(color: colors.primary);
Container(color: colors.primaryContainer);
Text('Error', style: TextStyle(color: colors.error));
Text('Subtle', style: TextStyle(color: colors.onSurfaceVariant));

// WRONG: Hardcoded hex values
Container(color: Color(0xFF4A7C59));  // Opaque, not theme-aware
```

**Key ColorScheme Properties:**

| Property | Usage |
|---|---|
| `primary` | Buttons, FABs, links, key actions |
| `onPrimary` | Text/icons on primary colour |
| `primaryContainer` | Chips, selected states, subtle highlights |
| `secondary` | Secondary actions, accent elements |
| `tertiary` | Tags, badges, third accent |
| `surface` | Cards, sheets, dialogs |
| `onSurface` | Primary text on surfaces |
| `onSurfaceVariant` | Secondary/muted text |
| `error` | Error text, borders, destructive actions |
| `outline` | Borders, dividers |
| `outlineVariant` | Subtle borders |

### 4f. Theme Persistence — `ThemeProvider`

Two notifiers track the variant (colour palette) and brightness (light/dark/system) independently.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme.dart';

const String _themeVariantKey = 'theme_variant';
const String _brightnessModeKey = 'brightness_mode';

/// Manages the selected ThemeVariant (colour palette).
class ThemeVariantNotifier extends StateNotifier<ThemeVariant> {
  ThemeVariantNotifier() : super(ThemeVariant.forest) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeVariantKey);
    if (saved != null) {
      state = ThemeVariant.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => ThemeVariant.forest,
      );
    }
  }

  Future<void> set(ThemeVariant variant) async {
    state = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeVariantKey, variant.name);
  }
}

/// Manages the brightness mode (light, dark, or system).
class BrightnessModeNotifier extends StateNotifier<ThemeMode> {
  BrightnessModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_brightnessModeKey);
    if (saved != null) {
      state = ThemeMode.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brightnessModeKey, mode.name);
  }
}

// ── Providers ──────────────────────────────────────────────

final themeVariantProvider =
    StateNotifierProvider<ThemeVariantNotifier, ThemeVariant>(
  (ref) => ThemeVariantNotifier(),
);

final brightnessModeProvider =
    StateNotifierProvider<BrightnessModeNotifier, ThemeMode>(
  (ref) => BrightnessModeNotifier(),
);

/// Light ThemeData for the current variant.
final lightThemeProvider = Provider<ThemeData>((ref) {
  final variant = ref.watch(themeVariantProvider);
  final schemeData = AppPalettes.getSchemeData(variant);
  return AppTheme.light(schemeData);
});

/// Dark ThemeData for the current variant.
final darkThemeProvider = Provider<ThemeData>((ref) {
  final variant = ref.watch(themeVariantProvider);
  final schemeData = AppPalettes.getSchemeData(variant);
  return AppTheme.dark(schemeData);
});
```

**Flow:** User selects variant → `themeVariantProvider` updates → `lightThemeProvider` + `darkThemeProvider` recompute → `MaterialApp` re-renders with smooth 300ms animation. Brightness mode can change independently (system/light/dark).

---

## 5. Models

### 5a. Auth Response Models

These models map the Bubble API login response into Dart objects.

#### `UserStruct` — Top-level API response

```dart
class UserStruct {
  final String status;
  final ResponseStruct? response;
  final int statusCode;
  final String? reason;
  final String? message;

  UserStruct({
    required this.status,
    this.response,
    this.statusCode = 200,
    this.reason,
    this.message,
  });

  factory UserStruct.fromJson(Map<String, dynamic> json) {
    return UserStruct(
      status: json['status'] as String? ?? '',
      response: json['response'] != null
          ? ResponseStruct.fromJson(json['response'] as Map<String, dynamic>)
          : null,
      statusCode: json['statusCode'] as int? ?? 200,
      reason: json['reason'] as String?,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'response': response?.toJson(),
    'statusCode': statusCode,
    'reason': reason,
    'message': message,
  };

  bool get isSuccess => status == 'success';
}
```

#### `ResponseStruct` — Nested auth response data

```dart
class ResponseStruct {
  final String token;
  final String userId;
  final int expires;
  final String? buildings;

  ResponseStruct({
    required this.token,
    required this.userId,
    required this.expires,
    this.buildings,
  });

  factory ResponseStruct.fromJson(Map<String, dynamic> json) {
    return ResponseStruct(
      token: json['token'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      expires: json['expires'] as int? ?? 0,
      buildings: json['buildings'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'user_id': userId,
    'expires': expires,
    'buildings': buildings,
  };
}
```

### 5b. Immutable Model Pattern — `UserProfile`

For any additional user profile data beyond auth, follow this pattern:

```dart
class UserProfile {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  UserProfile copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get fullName {
    if (firstName != null && lastName != null) return '$firstName $lastName';
    if (firstName != null) return firstName!;
    if (lastName != null) return lastName!;
    return email;
  }
}
```

**Model rules:**
1. All fields `final` — immutable.
2. `fromJson` factory — maps snake_case API fields to camelCase Dart fields.
3. `toJson` method — reverse mapping for writes.
4. `copyWith` — creates a modified copy without mutating the original.
5. Computed getters (`fullName`) for derived values.

### 5c. Adding New Models

When adding domain-specific models, follow the same pattern:

```dart
class MyModel {
  final String id;
  final String title;
  final DateTime createdAt;

  MyModel({required this.id, required this.title, required this.createdAt});

  factory MyModel.fromJson(Map<String, dynamic> json) => MyModel(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
  };

  MyModel copyWith({String? id, String? title, DateTime? createdAt}) => MyModel(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
  );
}
```

---

## 6. State Management (Riverpod)

### 6a. Provider Types — Decision Tree

| Need | Provider Type | Example |
|------|--------------|---------|
| Singleton service | `Provider` | `authRepositoryProvider` |
| One-shot async fetch | `FutureProvider` | `userProfileProvider` |
| Ongoing stream | `StreamProvider` | `authStateProvider` |
| Mutable state with logic | `StateNotifierProvider` | `userProfileNotifierProvider` |
| Simple mutable value | `StateProvider` | `selectedTabProvider` |

### 6b. Repository Provider Pattern

```dart
// Repository: pure data access, no UI awareness
class ApiRepository {
  final AuthRepository _authRepo;

  ApiRepository(this._authRepo);

  /// Make an authenticated GET request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedGet(String endpoint, {Map<String, String>? queryParams}) async {
    final token = _authRepo.authenticationToken;
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Make an authenticated POST request to a Bubble API endpoint.
  Future<Map<String, dynamic>> authenticatedPost(String endpoint, {Map<String, dynamic>? body}) async {
    final token = _authRepo.authenticationToken;
    if (token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$endpoint'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? jsonEncode(body) : null,
    );

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

// Provider: exposes repository as singleton
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return ApiRepository(authRepo);
});
```

### 6c. Auth State Chain

Four providers form a dependency chain:

```dart
// 1. Repository — singleton
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// 2. Auth state stream — emits on login/logout via BehaviorSubject
final authStateProvider = StreamProvider<BubbleAuthUser>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authUserStream;
});

// 3. Current user ID — derived from auth state
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (user) => user.loggedIn ? user.uid : null,
    orElse: () => null,
  );
});

// 4. Boolean convenience
final isAuthenticatedProvider = Provider<bool>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return userId != null;
});
```

**Why a chain?** Each provider has a single responsibility. `GoRouter` watches `isAuthenticatedProvider` for redirects. Screens watch `currentUserIdProvider` for user data. The stream automatically updates everything when auth state changes.

### 6d. User Profile Provider (Dual Pattern)

Two providers serve different needs:

```dart
// FutureProvider — one-shot fetch, auto-disposes, simple reads
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final apiRepo = ref.watch(apiRepositoryProvider);
  // Fetch profile from Bubble API endpoint
  final data = await apiRepo.authenticatedGet('appfetchprofile', queryParams: {'user_id': userId});
  return UserProfile.fromJson(data['response']);
});

// StateNotifierProvider — for screens that need to update the profile
class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  UserProfileNotifier(this._apiRepository, this._userId)
      : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  final ApiRepository _apiRepository;
  final String? _userId;

  Future<void> _loadProfile() async {
    if (_userId == null) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final data = await _apiRepository.authenticatedGet('appfetchprofile', queryParams: {'user_id': _userId!});
      final profile = UserProfile.fromJson(data['response']);
      state = AsyncValue.data(profile);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() async => await _loadProfile();
}

final userProfileNotifierProvider =
    StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final apiRepository = ref.watch(apiRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return UserProfileNotifier(apiRepository, userId);
});
```

**When to use which:**
- `userProfileProvider` — read-only screens (profile display, drawer header)
- `userProfileNotifierProvider` — edit profile screen (needs `refresh()`)

---

## 7. Auth System (Bubble API)

### 7a. API Configuration

```dart
// lib/core/config/api_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  /// Bubble API base URL (e.g. https://app.example.co.uk/version-test/api/1.1/wf/)
  static String get baseUrl => dotenv.env['BUBBLE_API_BASE_URL']!;
}
```

`.env` file:
```
BUBBLE_API_BASE_URL=https://app.example.co.uk/version-test/api/1.1/wf/
```

### 7b. Auth User Model

```dart
// lib/auth/bubble_auth_user.dart

/// Client-side auth state model.
class BubbleAuthUser {
  final bool loggedIn;
  final String? uid;
  final UserStruct? userData;

  BubbleAuthUser({
    required this.loggedIn,
    this.uid,
    this.userData,
  });
}
```

### 7c. Auth Repository

```dart
// lib/repositories/auth_repository.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import '../models/user_struct.dart';
import '../auth/bubble_auth_user.dart';

class AuthRepository {
  // ── In-memory auth state ──────────────────────────────
  String? _authenticationToken;
  String? _refreshToken;
  DateTime? _tokenExpiration;
  String? _uid;
  UserStruct? _userData;

  // ── Reactive auth stream ──────────────────────────────
  final _authUserSubject = BehaviorSubject<BubbleAuthUser>.seeded(
    BubbleAuthUser(loggedIn: false),
  );

  Stream<BubbleAuthUser> get authUserStream => _authUserSubject.stream;
  BubbleAuthUser get currentAuthUser => _authUserSubject.value;

  // ── Public accessors ──────────────────────────────────
  String? get authenticationToken => _authenticationToken;
  String? get refreshToken => _refreshToken;
  DateTime? get tokenExpiration => _tokenExpiration;
  String? get uid => _uid;
  UserStruct? get userData => _userData;
  bool get isAuthenticated => currentAuthUser.loggedIn;

  // ── SharedPreferences keys ────────────────────────────
  static const _keyToken = '_auth_authentication_token_';
  static const _keyRefreshToken = '_auth_refresh_token_';
  static const _keyTokenExpiration = '_auth_token_expiration_';
  static const _keyUid = '_auth_uid_';
  static const _keyUserData = '_auth_user_data_';

  // ── Initialization (called on app startup) ────────────
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    _authenticationToken = prefs.getString(_keyToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    _uid = prefs.getString(_keyUid);

    final expirationMs = prefs.getInt(_keyTokenExpiration);
    if (expirationMs != null) {
      _tokenExpiration = DateTime.fromMillisecondsSinceEpoch(expirationMs);
    }

    final userDataJson = prefs.getString(_keyUserData);
    if (userDataJson != null) {
      _userData = UserStruct.fromJson(jsonDecode(userDataJson));
    }

    // Check if token exists and is not expired
    final tokenExists = _authenticationToken != null;
    final tokenExpired = _tokenExpiration != null &&
        _tokenExpiration!.isBefore(DateTime.now());

    if (tokenExists && !tokenExpired) {
      _authUserSubject.add(BubbleAuthUser(
        loggedIn: true,
        uid: _uid,
        userData: _userData,
      ));
    } else {
      // Token expired or missing — clear state
      await _clearAuthState();
    }
  }

  // ── Login ─────────────────────────────────────────────
  Future<UserStruct> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}applogin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': escapeStringForJson(email),
        'password': escapeStringForJson(password),
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final userStruct = UserStruct.fromJson(data);

    if (!userStruct.isSuccess || userStruct.response == null) {
      throw Exception(userStruct.message ?? 'Failed to login. Please check your email and password.');
    }

    // Calculate token expiry
    final expiresInSeconds = userStruct.response!.expires;
    final expiryTime = DateTime.now().add(Duration(seconds: expiresInSeconds));

    // Store auth state
    _authenticationToken = userStruct.response!.token;
    _tokenExpiration = expiryTime;
    _uid = userStruct.response!.userId;
    _userData = userStruct;

    // Persist to SharedPreferences
    await _persistAuthData();

    // Emit new auth state
    _authUserSubject.add(BubbleAuthUser(
      loggedIn: true,
      uid: _uid,
      userData: _userData,
    ));

    return userStruct;
  }

  // ── Logout ────────────────────────────────────────────
  Future<void> signOut() async {
    await _clearAuthState();
  }

  // ── Persistence ───────────────────────────────────────
  Future<void> _persistAuthData() async {
    final prefs = await SharedPreferences.getInstance();

    if (_authenticationToken != null) {
      await prefs.setString(_keyToken, _authenticationToken!);
    } else {
      await prefs.remove(_keyToken);
    }

    if (_refreshToken != null) {
      await prefs.setString(_keyRefreshToken, _refreshToken!);
    } else {
      await prefs.remove(_keyRefreshToken);
    }

    if (_tokenExpiration != null) {
      await prefs.setInt(_keyTokenExpiration, _tokenExpiration!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_keyTokenExpiration);
    }

    if (_uid != null) {
      await prefs.setString(_keyUid, _uid!);
    } else {
      await prefs.remove(_keyUid);
    }

    if (_userData != null) {
      await prefs.setString(_keyUserData, jsonEncode(_userData!.toJson()));
    } else {
      await prefs.remove(_keyUserData);
    }
  }

  Future<void> _clearAuthState() async {
    _authenticationToken = null;
    _refreshToken = null;
    _tokenExpiration = null;
    _uid = null;
    _userData = null;

    await _persistAuthData();

    _authUserSubject.add(BubbleAuthUser(loggedIn: false));
  }

  /// Check if the current token is expired.
  bool get isTokenExpired {
    if (_tokenExpiration == null) return true;
    return _tokenExpiration!.isBefore(DateTime.now());
  }
}

/// Sanitise user input before sending to the API.
String escapeStringForJson(String input) {
  return input
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}
```

### 7d. Auth State Architecture

```
BehaviorSubject<BubbleAuthUser> (_authUserSubject)
        │
        ▼
authUserStream (broadcast stream)
        │
        ▼
authStateProvider (StreamProvider) listens
        │
        ▼
currentUserIdProvider (derived)
        │
        ▼
isAuthenticatedProvider (derived bool)
        │
        ▼
GoRouter redirect logic
```

### 7e. Token and Session Storage

Tokens and user data are persisted to **SharedPreferences** so the session survives app restarts.

| SharedPreferences Key | Value |
|----------------------|-------|
| `_auth_authentication_token_` | Bearer token string |
| `_auth_refresh_token_` | Refresh token string (stored but not currently used for rotation) |
| `_auth_token_expiration_` | Token expiry as milliseconds since epoch |
| `_auth_uid_` | User ID from the backend |
| `_auth_user_data_` | JSON-encoded `UserStruct` |

On initialization, the token is checked for expiration:
```dart
final tokenExists = authenticationToken != null;
final tokenExpired = tokenExpiration != null && tokenExpiration!.isBefore(DateTime.now());
// User is logged in only if token exists AND is not expired
```

### 7f. Email + Password Login Flow

```
┌──────────────────────────┐
│  Enter your email        │
│  ┌────────────────────┐  │
│  │ your@email.com     │  │
│  └────────────────────┘  │
│  Enter your password     │
│  ┌────────────────────┐  │
│  │ ••••••••           │  │
│  └────────────────────┘  │
│  [    Sign In    ]       │
└──────────────────────────┘
          │ login(email, password)
          ▼
    POST /applogin
          │
          ▼
    success → store token → navigate to /home
    failure → show SnackBar error
```

**Screen pattern:**
```dart
class LoginScreen extends ConsumerStatefulWidget { /* ... */ }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  Future<void> _handleLogin() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // GoRouter redirect handles navigation to /home
    } catch (e) {
      setState(() { _error = getErrorMessage(e); });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing2xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome Back', style: AppTypography.displayLarge),
              SizedBox(height: tokens.spacing3xl),

              AppTextField.email(
                controller: _emailController,
              ),
              SizedBox(height: tokens.spacingLg),

              AppTextField.password(
                controller: _passwordController,
              ),
              SizedBox(height: tokens.spacingXl),

              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: colors.error)),
                SizedBox(height: tokens.spacingLg),
              ],

              AppButton(
                text: 'Sign In',
                onPressed: _handleLogin,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 7g. Bubble API Endpoints

All protected endpoints require a `Bearer` token in the `Authorization` header.

| Endpoint | Method | Purpose | Auth Required |
|----------|--------|---------|:---:|
| `applogin` | POST | User login (email + password) | No |
| *(add your endpoints here)* | | | |

**Example: Adding a new authenticated endpoint call:**

```dart
// In ApiRepository or a domain-specific repository:
Future<List<Building>> fetchBuildings() async {
  final data = await authenticatedGet('appfetchbuildinglist');
  final list = data['response']['buildings'] as List;
  return list.map((b) => Building.fromJson(b)).toList();
}
```

### 7h. Security Notes

**Strengths:**
- Bearer token authentication on all data endpoints
- Token expiration checking on app startup
- Session data persisted via SharedPreferences (device-local, not accessible to other apps)
- Credentials are not stored; only the session token is persisted
- `escapeStringForJson()` sanitises user input before sending to the API

**Areas for Improvement:**
- **No refresh token rotation** — the refresh token field is stored but never used to obtain a new access token
- **No runtime token expiry check** — tokens are only validated on app startup, not before individual API calls. Consider adding a check in `authenticatedGet`/`authenticatedPost`.
- **No server-side logout** — `signOut()` only clears local state; the token may remain valid server-side
- **No password reset flow** — users cannot recover their account from the app
- **No user registration** — new accounts must be created outside the app (in Bubble admin)
- **No role-based access control** — all authenticated users have identical permissions
- **No multi-factor authentication**
- **No registration, social login, or magic link auth** — email + password only

---

## 8. Routing (GoRouter)

### 8a. Template Routes

```dart
final goRouterProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return GoRouter(
    redirect: (context, state) {
      final isAuth = isAuthenticated;
      final location = state.matchedLocation;

      final isGoingToAuth = location == '/login' || location == '/';

      // Default: authenticated → /home, unauthenticated → /
      if (location == '' || location == '/') {
        return isAuth ? '/home' : '/';
      }

      // Redirect to login for protected routes when not authenticated
      if (!isAuth && !isGoingToAuth) return '/login';

      // Redirect authenticated users away from auth pages
      if (isAuth && isGoingToAuth && location != '/') return '/home';

      return null;
    },
    routes: [
      GoRoute(path: '/', name: 'welcome',
        builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', name: 'login',
        builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', name: 'home',
        builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/profile', name: 'profile',
        builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings', name: 'settings',
        builder: (context, state) => const SettingsScreen()),
      // Add domain-specific routes here
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});
```

### 8b. Route Classification

| Route | Auth Required | Purpose |
|-------|:---:|---------|
| `/` | No | Welcome/landing screen |
| `/login` | No | Login screen |
| `/home` | Yes | Main app (bottom nav + drawer) |
| `/profile` | Yes | View own profile |
| `/settings` | Yes | App settings |

### 8c. Adding New Routes

```dart
// 1. Add route to GoRouter
GoRoute(
  path: '/my-feature',
  name: 'my-feature',
  builder: (context, state) => const MyFeatureScreen(),
),

// 2. Navigate to it
context.go('/my-feature');       // Replace current route
context.push('/my-feature');     // Push onto stack

// 3. With parameters
GoRoute(
  path: '/item/:itemId',
  name: 'item-detail',
  builder: (context, state) {
    final itemId = state.pathParameters['itemId']!;
    return ItemDetailScreen(itemId: itemId);
  },
),
```

---

## 9. Navigation — Home Screen

### 9a. Bottom Navigation Bar

```dart
class HomeScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});
  // ...
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Tab screens — use IndexedStack to preserve state
  final List<Widget> _screens = [
    const PlaceholderTab(title: 'Home'),
    const PlaceholderTab(title: 'Explore'),
    const PlaceholderTab(title: 'Activity'),
    const PlaceholderTab(title: 'More'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNavBar(context, tokens, colors),
    );
  }
}
```

**Why `IndexedStack`?** Each tab preserves its scroll position and state. Only the visible tab is rendered, but all tabs remain alive in the tree.

**Bottom nav bar pattern (custom rounded):**

```dart
Widget _buildBottomNavBar(BuildContext context, AppThemeTokens tokens, ColorScheme colors) {
  return Container(
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.radiusXl)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2)),
      ],
    ),
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacingLg, vertical: tokens.spacingSm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.home_outlined, Icons.home, 'Home'),
            _navItem(1, Icons.explore_outlined, Icons.explore, 'Explore'),
            _navItem(2, Icons.notifications_outlined, Icons.notifications, 'Activity'),
            _navItem(3, Icons.menu, Icons.menu, 'More'),
          ],
        ),
      ),
    ),
  );
}

Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
  final isActive = _currentIndex == index;
  final colors = context.colors;

  return GestureDetector(
    onTap: () => setState(() => _currentIndex = index),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? colors.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isActive ? activeIcon : icon,
            color: isActive ? colors.primary : colors.onSurfaceVariant),
          if (isActive) ...[
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: colors.primary, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    ),
  );
}
```

### 9b. Sidebar Drawer

```dart
Widget _buildDrawer(BuildContext context) {
  final colors = context.colors;
  final tokens = context.tokens;
  final authUser = ref.watch(authStateProvider);

  return Drawer(
    child: Column(
      children: [
        // Profile header
        authUser.when(
          data: (user) => _buildDrawerHeader(user, colors, tokens),
          loading: () => const DrawerHeaderSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
        ),

        // Menu items
        ListTile(
          leading: const Icon(Icons.person_outlined),
          title: const Text('Profile'),
          onTap: () {
            Navigator.pop(context); // close drawer
            context.push('/profile');
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () {
            Navigator.pop(context);
            context.push('/settings');
          },
        ),

        const Spacer(),
        const Divider(),

        // Sign out
        ListTile(
          leading: Icon(Icons.logout, color: colors.error),
          title: Text('Sign Out', style: TextStyle(color: colors.error)),
          onTap: () => _showSignOutConfirmation(context),
        ),
        SizedBox(height: tokens.spacingLg),
      ],
    ),
  );
}

Widget _buildDrawerHeader(BubbleAuthUser? user, ColorScheme colors, AppThemeTokens tokens) {
  return DrawerHeader(
    decoration: BoxDecoration(color: colors.primary),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text(
            user?.uid?.characters.first.toUpperCase() ?? '?',
            style: const TextStyle(fontSize: 24, color: Colors.white),
          ),
        ),
        SizedBox(height: tokens.spacingSm),
        Text(user?.uid ?? 'Guest',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
```

---

## 10. Settings & Account

### 10a. Theme Switcher

```dart
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final currentVariant = ref.watch(themeVariantProvider);
    final currentBrightness = ref.watch(brightnessModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Appearance section
          _buildSectionHeader('Appearance', tokens),
          _buildThemeSelector(context, ref, currentVariant, tokens),
          _buildBrightnessSelector(context, ref, currentBrightness, tokens),

          // Account section
          _buildSectionHeader('Account', tokens),
          _buildAccountSection(context, ref),

          // About section
          _buildSectionHeader('About', tokens),
          _buildAboutSection(context),
        ],
      ),
    );
  }
}
```

**Theme variant selector with palette preview circles:**

```dart
Widget _buildThemeSelector(BuildContext context, WidgetRef ref,
    ThemeVariant currentVariant, AppThemeTokens tokens) {
  final brightness = Theme.of(context).brightness;

  return Padding(
    padding: EdgeInsets.symmetric(horizontal: tokens.spacingLg),
    child: Wrap(
      spacing: tokens.spacingSm,
      runSpacing: tokens.spacingSm,
      children: ThemeVariant.values.map((variant) {
        final isSelected = variant == currentVariant;
        final previewColors = AppPalettes.getPreviewColors(variant, brightness);

        return GestureDetector(
          onTap: () {
            ref.read(themeVariantProvider.notifier).set(variant);
          },
          child: Container(
            padding: EdgeInsets.all(tokens.spacingSm),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? context.colors.primary : context.colors.outline,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
            child: Column(
              children: [
                // Two stacked circles showing background + primary colour
                Stack(
                  children: [
                    CircleAvatar(radius: 16, backgroundColor: previewColors[0]),
                    Positioned(
                      right: 0, bottom: 0,
                      child: CircleAvatar(radius: 10, backgroundColor: previewColors[1]),
                    ),
                  ],
                ),
                SizedBox(height: tokens.spacingXs),
                Text(variant.displayName, style: AppTypography.labelSmall),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}
```

**Brightness mode selector:**

```dart
Widget _buildBrightnessSelector(BuildContext context, WidgetRef ref,
    ThemeMode currentMode, AppThemeTokens tokens) {
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: tokens.spacingLg, vertical: tokens.spacingSm),
    child: SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
        ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
      ],
      selected: {currentMode},
      onSelectionChanged: (selected) {
        ref.read(brightnessModeProvider.notifier).set(selected.first);
      },
    ),
  );
}
```

### 10b. Account Section

```dart
Widget _buildAccountSection(BuildContext context, WidgetRef ref) {
  return Column(
    children: [
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sign Out'),
        onTap: () => _showSignOutDialog(context, ref),
      ),
    ],
  );
}

Future<void> _showSignOutDialog(BuildContext context, WidgetRef ref) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign Out?'),
      content: const Text('Are you sure you want to sign out?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Sign Out', style: TextStyle(color: context.colors.error)),
        ),
      ],
    ),
  );

  if (proceed != true || !context.mounted) return;

  await ref.read(authRepositoryProvider).signOut();
  // Auth state change triggers GoRouter redirect to /login
}
```

### 10c. About Section

```dart
Widget _buildAboutSection(BuildContext context) {
  return FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snapshot) {
      final version = snapshot.data?.version ?? '...';
      final buildNumber = snapshot.data?.buildNumber ?? '';
      return ListTile(
        leading: const Icon(Icons.info_outlined),
        title: const Text('App Version'),
        subtitle: Text('v$version ($buildNumber)'),
      );
    },
  );
}
```

---

## 11. Common Widgets

### 11a. AppButton

Three variants with loading state and optional icon.

```dart
enum AppButtonVariant { primary, outline, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget child = isLoading
        ? SizedBox(
            height: tokens.iconSm, width: tokens.iconSm,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: tokens.iconSm),
                SizedBox(width: tokens.spacingSm),
              ],
              Text(text),
            ],
          );

    final style = switch (variant) {
      AppButtonVariant.primary => FilledButton.styleFrom(
        minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
      ),
      AppButtonVariant.outline => OutlinedButton.styleFrom(
        minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
      ),
      AppButtonVariant.ghost => TextButton.styleFrom(
        minimumSize: fullWidth ? const Size(double.infinity, 48) : null,
      ),
    };

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: isLoading ? null : onPressed, style: style, child: child,
      ),
      AppButtonVariant.outline => OutlinedButton(
        onPressed: isLoading ? null : onPressed, style: style, child: child,
      ),
      AppButtonVariant.ghost => TextButton(
        onPressed: isLoading ? null : onPressed, style: style, child: child,
      ),
    };
  }
}
```

### 11b. AppTextField

```dart
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final int maxLines;

  /// Email input with defaults
  factory AppTextField.email({
    required TextEditingController controller,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) => AppTextField(
    controller: controller,
    label: 'Email',
    hint: 'your@email.com',
    prefixIcon: Icons.email_outlined,
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.email],
    validator: validator,
    onChanged: onChanged,
  );

  /// Password input with defaults
  factory AppTextField.password({
    required TextEditingController controller,
    String? Function(String?)? validator,
    String label = 'Password',
  }) => AppTextField(
    controller: controller,
    label: label,
    prefixIcon: Icons.lock_outlined,
    obscureText: true,
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.password],
    validator: validator,
  );

  /// Generic text input
  factory AppTextField.name({
    required TextEditingController controller,
    String label = 'Name',
    ValueChanged<String>? onChanged,
  }) => AppTextField(
    controller: controller,
    label: label,
    prefixIcon: Icons.person_outlined,
    textInputAction: TextInputAction.next,
    autofillHints: const [AutofillHints.name],
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
```

**Usage:**
```dart
AppTextField.email(controller: _emailController, validator: _validateEmail);
AppTextField.password(controller: _passwordController);
AppTextField.name(controller: _firstNameController, label: 'First Name');
```

### 11c. Barrel Export

```dart
// widgets/common/widgets.dart
export 'app_button.dart';
export 'app_text_field.dart';
export 'app_card.dart';
// Add new widgets here
```

---

## 12. Error Handling

### 12a. `getErrorMessage()` Utility

Centralised error-to-message mapper. Handles HTTP errors, network errors, and timeouts. All errors from the Bubble API are plain HTTP responses.

```dart
String getErrorMessage(Object error) {
  if (error is HttpException) return _getHttpErrorMessage(error);

  if (error is Exception) {
    final message = error.toString().toLowerCase();
    if (message.contains('socketexception') || message.contains('network')) {
      return 'Unable to connect. Please check your internet connection.';
    }
    if (message.contains('timeout')) {
      return 'The request timed out. Please try again.';
    }
    if (message.contains('not authenticated') || message.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (message.contains('failed to login')) {
      return 'Failed to login. Please check your email and password.';
    }
    final clean = error.toString().replaceAll('Exception: ', '');
    if (clean.length < 100) return clean;
  }

  return 'Something went wrong. Please try again.';
}

String _getHttpErrorMessage(HttpException error) {
  final msg = error.message.toLowerCase();
  if (msg.contains('401') || msg.contains('unauthorized')) {
    return 'Your session has expired. Please sign in again.';
  }
  if (msg.contains('403') || msg.contains('forbidden')) {
    return 'You do not have permission to perform this action.';
  }
  if (msg.contains('404') || msg.contains('not found')) {
    return 'The requested item was not found.';
  }
  if (msg.contains('500') || msg.contains('server error')) {
    return 'A server error occurred. Please try again later.';
  }
  return 'An error occurred while processing your request.';
}
```

### 12b. Repository Error Pattern

```dart
// RIGHT: Repository catches and re-throws with context
Future<Map<String, dynamic>> authenticatedGet(String endpoint, ...) async {
  try {
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }
    return jsonDecode(response.body);
  } on SocketException {
    throw Exception('Unable to connect. Please check your internet connection.');
  } on TimeoutException {
    throw Exception('The request timed out. Please try again.');
  }
}

// Screen uses getErrorMessage for display
try {
  await apiRepo.authenticatedGet('appfetchbuildings');
} catch (e) {
  setState(() { _error = getErrorMessage(e); });
}
```

---

## 13. Anti-Patterns Quick Reference

| Don't | Do Instead |
|-------|------------|
| Call Bubble API from widgets | Use Repository → Provider → Widget |
| Hardcode spacing (`16`, `24`) | Use `tokens.spacingLg`, `tokens.spacingXl` |
| Hardcode colours (`Color(0xFF...)`) | Use `context.colors.primary`, `context.colors.surface` |
| Build ThemeData manually | Use `FlexThemeData.light()` / `.dark()` via `AppTheme` |
| Define component themes manually | Configure via `FlexSubThemesData` properties |
| Inline `TextStyle(fontSize: ...)` | Use `AppTypography.bodyLarge` or `Theme.of(context).textTheme` |
| Show raw error messages | Use `getErrorMessage(e)` |
| Create global singletons | Use Riverpod providers |
| Use `setState` for shared state | Use Riverpod `StateProvider` or `StateNotifierProvider` |
| Store secrets in code | Use `.env` file (git-ignored) |
| Use magic numbers for radius | Use `tokens.radiusMd` for custom widgets (FlexColorScheme handles components) |
| Mutate model fields | Use `copyWith()` on immutable models |
| Make API calls without checking token | Check `isTokenExpired` before API calls |
| Store user passwords locally | Only persist the session token, never credentials |

---

## Source File Index

| File | Section | Purpose |
|------|---------|---------|
| `lib/main.dart` | 3 | Entry point, ProviderScope, text scaling, light/dark themes |
| `lib/core/config/api_config.dart` | 7a | Loads .env credentials (Bubble API base URL) |
| `lib/core/router/app_router.dart` | 8 | GoRouter, auth redirects |
| `lib/theme/app_theme_tokens.dart` | 4a | Spacing/radius/icon tokens (ThemeExtension) |
| `lib/theme/app_palettes.dart` | 4b | ThemeVariant enum + FlexSchemeData seed colour definitions |
| `lib/theme/app_theme.dart` | 4c | FlexThemeData wrapper + ThemeExtension registration |
| `lib/theme/app_typography.dart` | 4d | Text style constants |
| `lib/providers/theme_provider.dart` | 4f | Theme variant + brightness persistence (SharedPreferences) |
| `lib/models/user_struct.dart` | 5a | Bubble API login response model |
| `lib/models/response_struct.dart` | 5a | Nested auth response (token, userId, expires) |
| `lib/models/user_profile.dart` | 5b | Immutable user profile model |
| `lib/auth/bubble_auth_user.dart` | 7b | Client-side auth state model |
| `lib/providers/auth_provider.dart` | 6c | Auth state chain (4 providers) |
| `lib/providers/user_profile_provider.dart` | 6d | Dual provider (Future + StateNotifier) |
| `lib/repositories/auth_repository.dart` | 7c | Auth + token management + persistence |
| `lib/repositories/api_repository.dart` | 6b | Authenticated API calls to Bubble |
| `lib/screens/auth/login_screen.dart` | 7f | Email + password login |
| `lib/screens/home_screen.dart` | 9 | Bottom nav + drawer |
| `lib/screens/settings_screen.dart` | 10 | Theme + brightness switcher, account, about |
| `lib/utils/error_utils.dart` | 12 | Error message mapper |
| `lib/widgets/common/app_button.dart` | 11a | Button (3 variants) |
| `lib/widgets/common/app_text_field.dart` | 11b | Text field (factory constructors) |

---

## pubspec.yaml — Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Theme
  flex_color_scheme: ^8.4.0

  # State management
  flutter_riverpod: ^2.5.0

  # Routing
  go_router: ^14.0.0

  # HTTP & API
  http: ^1.2.0

  # Reactive streams
  rxdart: ^0.28.0

  # Environment
  flutter_dotenv: ^5.1.0

  # Local storage
  shared_preferences: ^2.2.0

  # App info
  package_info_plus: ^8.0.0
```

All backend communication is via plain HTTP to the Bubble REST API.
