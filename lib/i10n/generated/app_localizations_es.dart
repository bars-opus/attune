// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'Tu aplicación innovadora';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonLogin => 'Iniciar sesión';

  @override
  String get commonLogout => 'Cerrar sesión';

  @override
  String get commonDone => 'Hecho';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonAccept => 'Aceptar';

  @override
  String get commonReject => 'Rechazar';

  @override
  String get introGetStarted => 'Comenzar';

  @override
  String get actionsBlock => 'Bloquear usuario';

  @override
  String get actionsReport => 'Reportar usuario';

  @override
  String get actionsSend => 'Enviar al chat';

  @override
  String get actionsShare => 'Compartir';

  @override
  String get actionsCopy => 'Copiar enlace';

  @override
  String get appInfoVersion => 'Versión';

  @override
  String get appInfoReleased => 'Publicado';

  @override
  String get appInfoPackageName => 'Nombre del Paquete';

  @override
  String get appInfoDeveloper => 'Nombre del Desarrollador';

  @override
  String get appInfoSupportEmail => 'Email de Soporte';

  @override
  String get appInfoTechnicalDetails => 'Detalles Técnicos';

  @override
  String get appInfoBundleID => 'ID del Paquete';

  @override
  String get appInfoBuildVersion => 'Versión de Compilación';

  @override
  String get appInfoBuildNumber => 'Número de Compilación';

  @override
  String get appInfoReleaseDate => 'Fecha de Lanzamiento';

  @override
  String get appInfoAppSize => 'Tamaño de la App';

  @override
  String appInfoOverview(String appName) {
    return '$appName es una aplicación móvil moderna construida con seguridad robusta y funcionalidad, diseñada para proporcionar una experiencia de usuario excepcional con arquitectura limpia y optimización de rendimiento.';
  }

  @override
  String introTitle(String appName) {
    return 'Bienvenido a $appName';
  }

  @override
  String get introFeature1Title => 'Ver Tu Progreso';

  @override
  String get introFeature1Description => 'Sigue tus hitos de desarrollo con análisis detallados y perspectivas';

  @override
  String get introFeature2Title => 'Explorar Plantillas';

  @override
  String get introFeature2Description => 'Descubre componentes y pantallas preconstruidos para desarrollo rápido';

  @override
  String get introFeature3Title => 'Comienza Rápidamente';

  @override
  String get introFeature3Description => 'Inicia tu proyecto con configuración cero y mejores prácticas';

  @override
  String get appleSignIn => 'Iniciar sesión con Apple';

  @override
  String get googleSignIn => 'Iniciar sesión con Google';

  @override
  String get appleRegister => 'Registrarse con Apple';

  @override
  String get googleRegister => 'Registrarse con Google';

  @override
  String get emailAndPassword => 'Ingresar correo y contraseña';

  @override
  String get signInTitle => 'Iniciar sesión';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get legalConsentPart1 => 'Por favor, lea los ';

  @override
  String get legalConsentPart2 => 'términos y condiciones';

  @override
  String legalConsentPart3(String appName) {
    return ' y otros documentos legales que rigen su uso de $appName.';
  }

  @override
  String get emailTitle => 'Correo electrónico';

  @override
  String get passwordTitle => 'Contraseña';

  @override
  String get loginEmailLabel => 'Dirección de correo electrónico';

  @override
  String get loginEmailHint => 'Introduce tu correo electrónico';

  @override
  String get loginPasswordLabel => 'Contraseña';

  @override
  String get loginPasswordHint => 'Introduce tu contraseña';

  @override
  String get loginForgotPasswordPart1 => '¿Has olvidado tu contraseña? ';

  @override
  String get loginForgotPasswordPart2 => 'Toca aquí';

  @override
  String get loginForgotPasswordPart3 => ' para restablecer tu contraseña?';

  @override
  String get commonConfirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get commonConfirmPasswordHint => 'Por favor, confirma tu contraseña';

  @override
  String get commonPasswordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get commonPasswordConfirmRequired => 'Por favor, confirma tu contraseña';

  @override
  String commonFieldIsValid(String field) {
    return '$field es válido';
  }

  @override
  String get commonPleaseWait => 'Por favor, espera a que se complete la operación actual';

  @override
  String get commonUnexpectedError => 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo.';

  @override
  String get commonSomethingWentWrong => 'Algo salió mal. Por favor, inténtalo de nuevo.';

  @override
  String get commonEnterEmailAndRetry => 'Por favor, introduce tu dirección de correo electrónico e inténtalo de nuevo';

  @override
  String get commonLearnMore => 'Aprende más';

  @override
  String get authSignUpVerificationSent => '¡Correo de verificación enviado! Por favor, revisa tu bandeja de entrada.';

  @override
  String authSignUpFailed(String error) {
    return 'Registro fallido: $error';
  }

  @override
  String get authForgotPasswordTitle => '¿Olvidaste tu contraseña?';

  @override
  String get authForgotPasswordSubtitle => 'Introduce tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.';

  @override
  String get authSendResetLink => 'Enviar enlace de restablecimiento';

  @override
  String get authBackToSignIn => 'Volver al inicio de sesión';

  @override
  String get authUsernameScreenTitle => 'Elige tu nombre de usuario';

  @override
  String get authUsernameScreenSubtitle => 'Así es como te ven otros. Puedes cambiarlo más tarde.';

  @override
  String get authUsernameLabel => 'Nombre de usuario';

  @override
  String get authUsernameHint => 'Introduce un nombre de usuario';

  @override
  String authUsernameMinLength(int min) {
    return 'El nombre de usuario debe tener al menos $min caracteres';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'El nombre de usuario debe tener como máximo $max caracteres';
  }

  @override
  String get authUsernameFormatError => 'Solo se permiten letras, números y guiones bajos';

  @override
  String get authUsernameTaken => 'Este nombre de usuario ya está en uso';

  @override
  String get authUsernameCheckError => 'No se pudo comprobar la disponibilidad. Por favor, inténtalo de nuevo.';

  @override
  String get authUsernameSaveError => 'No se pudo guardar tu nombre de usuario. Por favor, inténtalo de nuevo.';

  @override
  String get authUsernameSavedSuccess => '¡Nombre de usuario guardado exitosamente!';

  @override
  String get authUpdatePasswordTitle => 'Crear nueva contraseña';

  @override
  String get authUpdatePasswordButton => 'Actualizar contraseña';

  @override
  String get authUpdatePasswordSuccess => 'Contraseña actualizada exitosamente. Por favor, inicia sesión de nuevo.';

  @override
  String get authPasswordResetSentTitle => 'Revisa tu correo electrónico';

  @override
  String get authPasswordResetSentBody => 'Enviamos un enlace para restablecer tu contraseña a';

  @override
  String get authPasswordResetSentNote => 'Toca el enlace en el correo electrónico para establecer una nueva contraseña. El enlace expira en 1 hora.';

  @override
  String get authGuestHello => '¡Hola!';

  @override
  String authGuestOverview(String appName) {
    return 'Estás navegando $appName como invitado. Inicia sesión con tu número de teléfono para comenzar tu espacio compartido con tu pareja – solo toma unos segundos.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Bienvenido a\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Bienvenido a la plataforma que creamos para ti. Disfruta y diviértete – lo mejor está esperándote.';

  @override
  String get authReadLegalities => 'Leer avisos legales';

  @override
  String get authPasswordRequired => 'Por favor, introduce tu contraseña';

  @override
  String get authCreatingAccount => 'Creando cuenta...';

  @override
  String get authAccountCreatedSuccess => '¡Cuenta creada exitosamente!';

  @override
  String get authCheckEmailToConfirm => 'Por favor, revisa tu correo electrónico para confirmar tu cuenta';

  @override
  String get authSigningInWithGoogle => 'Iniciando sesión con Google...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Error al iniciar sesión con Google: $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Autenticando con Apple...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Error al iniciar sesión con Apple: $error';
  }

  @override
  String get authSendingResetEmail => 'Enviando correo de restablecimiento...';

  @override
  String get authResetEmailSent => 'Correo de restablecimiento enviado. Revisa tu bandeja de entrada.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Error al restablecer contraseña: $error';
  }

  @override
  String get authVerifyEmailTitle => 'Revisa tu correo electrónico';

  @override
  String get authVerifyEmailSubtitle => 'Enviamos un enlace de confirmación a';

  @override
  String get authVerifyEmailNote => 'Toca el enlace en el correo para verificar tu cuenta y continuar.';

  @override
  String get authConfirmationResent => 'Correo de confirmación reenviado. Revisa tu bandeja de entrada.';

  @override
  String get authResendFailed => 'Error al reenviar el correo. Por favor, inténtalo de nuevo.';

  @override
  String get authResendEmailButton => 'Reenviar correo de confirmación';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'Reenviar correo (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Seleccionar moneda';

  @override
  String get currencySelectorNoSelected => 'Ninguna moneda seleccionada';

  @override
  String get currencySelectorTitle => 'Seleccionar moneda';

  @override
  String get currencySelectorSearchHint => 'Buscar por moneda, código o bandera...';

  @override
  String get currencySelectorNoResults => 'No se encontraron monedas';

  @override
  String get discoverScreenTitle => 'Descubrir';

  @override
  String get discoverSearchHint => 'Buscar...';

  @override
  String get discoverAllShopsRegion => 'Todas las tiendas en tu región';

  @override
  String get discoverAllFreelancers => 'Todos los freelancers cerca de ti';

  @override
  String get discoverMarketplaceTitle => 'Mercado';

  @override
  String get discoverMarketplaceSubtitle => 'Compra productos de belleza con pago contra entrega';

  @override
  String get discoverBrowseProducts => 'Explorar productos';

  @override
  String get discoverMyOrders => 'Mis pedidos';

  @override
  String get discoverCartTooltip => 'Carrito';

  @override
  String get homeScheduleTabLabel => 'Horario';

  @override
  String get homeDashboardTabLabel => 'Panel';

  @override
  String get homeMapTabLabel => 'Mapa';

  @override
  String get validationRequired => 'Este campo es obligatorio';

  @override
  String get validationEmailInvalid => 'Por favor, introduce una dirección de correo electrónico válida';

  @override
  String validationPasswordLength(int minLength) {
    return 'La contraseña debe tener al menos $minLength caracteres';
  }

  @override
  String get validationPasswordUppercase => 'La contraseña debe incluir al menos una letra mayúscula';

  @override
  String get loggingInIndicatorText => 'Iniciando sesión...';

  @override
  String get loginSuccessful => '¡Inicio de sesión exitoso!\nBienvenido de nuevo';

  @override
  String get errorLoginFailed => 'Error al iniciar sesión. Por favor, verifica tus credenciales';

  @override
  String get errorNetwork => 'Error de red. Por favor, verifica tu conexión';

  @override
  String get homeTitle => 'Inicio';

  @override
  String get profileTitle => 'Perfil';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Nombre';

  @override
  String get editProfileNameFieldLabel => 'Nombre completo';

  @override
  String get editProfileUserFieldNameTitle => 'Nombre de usuario';

  @override
  String get editProfileUsernameFieldLabel => '@nombredeusuario';

  @override
  String get editProfileBioFieldTitle => 'Biografía';

  @override
  String get editProfileBioFieldLabel => 'Cuéntanos sobre ti';

  @override
  String get editProfileScreenTitle => 'Editar perfil';

  @override
  String get editProfileSettingTitle => 'Configuración de cuenta';

  @override
  String get editProfileSettingSubtitle => 'Administra tu cuenta';

  @override
  String get editProfileScreenEditShopTitle => 'Editar Tienda';

  @override
  String get editProfileScreenEditShopSubtitle => 'Cambia la información de tu tienda';

  @override
  String get languageScreenSubtitle => 'Elige tu idioma preferido para la interfaz de la app. Esto no afectará la configuración de tu dispositivo.';

  @override
  String get languageScreeUseDeviceLang => 'Usar Idioma del Dispositivo.';

  @override
  String get languageScreeUseDeviceLangNote => 'Esto se restablecerá para que coincida con el idioma del sistema de tu dispositivo.';

  @override
  String get settingsScreenTitle => 'Configuración';

  @override
  String get accountSectionTitle => 'Cuenta';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Perfil';

  @override
  String get profileItemSubtitle => 'Administra tus datos personales';

  @override
  String get locationItemTitle => 'Cambiar Ubicación';

  @override
  String get locationItemSubtitle => 'Cambia tu ciudad actual';

  @override
  String get saveItemTitle => 'Contenidos Guardados';

  @override
  String get saveItemSubtitle => 'Contenidos que has guardado';

  @override
  String get notificationsItemTitle => 'Notificaciones';

  @override
  String get notificationsItemSubtitle => 'Gestiona notificaciones push y por correo';

  @override
  String get blockedItemTitle => 'Cuentas Bloqueadas';

  @override
  String get blockedItemSubtitle => 'Cuentas que has bloqueado';

  @override
  String get mutedItemTitle => 'Cuentas Silenciadas';

  @override
  String get mutedItemSubtitle => 'Cuentas anónimas de Opinions que has silenciado';

  @override
  String get qrCodeItemTitle => 'Compartir Código QR';

  @override
  String get qrCodeItemSubtitle => 'Comparte tu código QR de cuenta';

  @override
  String get shareProfileItemTitle => 'Compartir Perfil';

  @override
  String get shareProfileItemSubtitle => 'Comparte tu perfil con amigos';

  @override
  String get appSettingsSectionTitle => 'Configuración de la App';

  @override
  String get appSettingsSectionSubtitle => 'Personaliza tu experiencia';

  @override
  String get themeItemTitle => 'Tema';

  @override
  String get themeItemSubtitle => 'Claro, Oscuro o Sistema';

  @override
  String get languageItemTitle => 'Idioma';

  @override
  String get languageItemSubtitle => 'Cambia el idioma de la app';

  @override
  String get biometricItemTitle => 'Inicio Biométrico';

  @override
  String get biometricItemSubtitle => 'Usa Face ID o Touch ID';

  @override
  String get supportSectionTitle => 'Soporte';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'Guía de Usuario';

  @override
  String get guideItemSubtitle => 'Documentación y tutoriales';

  @override
  String get helpItemTitle => 'Contactar Soporte';

  @override
  String get helpItemSubtitle => 'Obtén ayuda con la app';

  @override
  String get feedbackItemTitle => 'Enviar Comentarios';

  @override
  String get feedbackItemSubtitle => 'Comparte tus pensamientos';

  @override
  String get rateItemTitle => 'Calificar la App';

  @override
  String get rateItemSubtitle => 'Deja una reseña';

  @override
  String appInfoItemTitle(String appName) {
    return 'Acerca de $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Información técnica';

  @override
  String get legalSectionTitle => 'Legal';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Términos, Privacidad y Políticas';

  @override
  String get termsItemSubtitle => 'Lee nuestros términos';

  @override
  String get licensesItemTitle => 'Licencias de Código Abierto';

  @override
  String get licensesItemSubtitle => 'Bibliotecas y licencias de terceros';

  @override
  String get accountActionsSectionTitle => 'Acciones de Cuenta';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Desactivar';

  @override
  String get deactivateItemSubtitle => 'Desactiva tu cuenta';

  @override
  String get deleteItemTitle => 'Eliminar Cuenta';

  @override
  String get deleteItemSubtitle => 'Elimina tu cuenta permanentemente';

  @override
  String get logoutItemTitle => 'Cerrar Sesión';

  @override
  String get logoutItemSubtitle => 'Cierra sesión en tu cuenta';

  @override
  String get loadingDefaultMessage => 'Cargando...';

  @override
  String get emptyStateNoDataTitle => 'Aún no hay nada aquí';

  @override
  String get emptyStateNoDataSubtitle => 'Cuando haya algo que mostrar, aparecerá aquí.';

  @override
  String get emptyStateNoResultsTitle => 'Sin coincidencias';

  @override
  String get emptyStateNoResultsSubtitle => 'Prueba con otra palabra u otro filtro.';

  @override
  String get emptyStateNoInternetTitle => 'Estás sin conexión';

  @override
  String get emptyStateNoInternetSubtitle => 'Verifica tu conexión e intenta de nuevo.';

  @override
  String get emptyStateNoMessagesTitle => 'Aún no hay mensajes';

  @override
  String get emptyStateNoMessagesSubtitle => 'Saluda para empezar vuestra conversación.';

  @override
  String get emptyStateRefresh => 'Actualizar';

  @override
  String get emptyStateClearFilters => 'Limpiar filtros';

  @override
  String get emptyStateRetry => 'Reintentar';

  @override
  String get emptyStateStartChat => 'Saludar';

  @override
  String get errorNetworkTitle => 'Error de conexión';

  @override
  String get errorNetworkSubtitle => 'No se pudo conectar al servidor. Verifica tu conexión a internet.';

  @override
  String get errorServerTitle => 'Error del servidor';

  @override
  String get errorServerSubtitle => 'Algo salió mal de nuestro lado. Por favor, intenta más tarde.';

  @override
  String get errorClientTitle => 'Error en la solicitud';

  @override
  String get errorClientSubtitle => 'Hubo un problema con tu solicitud. Por favor, verifica e intenta de nuevo.';

  @override
  String get errorParsingTitle => 'Error de datos';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'No se pudo procesar el/la $dataType. Esto podría ser un problema temporal.';
  }

  @override
  String get errorPermissionTitle => 'Acceso denegado';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'No tienes permiso para acceder a este/esta $dataType.';
  }

  @override
  String get errorGenericTitle => 'Algo salió mal';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'Ocurrió un error inesperado al cargar $dataType. Por favor, intenta de nuevo.';
  }

  @override
  String get errorRetry => 'Reintentar';

  @override
  String get errorCheckSettings => 'Verificar configuración';

  @override
  String get errorReport => 'Reportar problema';

  @override
  String get errorGoBack => 'Volver';

  @override
  String get errorRefresh => 'Actualizar';

  @override
  String get errorRequestAccess => 'Solicitar acceso';

  @override
  String get errorContactSupport => 'Contactar soporte';

  @override
  String get eulaTitle => 'Acuerdo de Licencia de Usuario Final';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'Este Acuerdo de Licencia de Usuario Final (\"EULA\") es un acuerdo legal entre usted y Bars Opus, Ltd. para $appName.\n\nAl instalar, acceder o usar $appName, usted acepta estar sujeto a los términos de este EULA. $appName está licenciado, no vendido, para su uso solo bajo los términos de esta licencia. Bars Opus, Ltd. se reserva todos los derechos no expresamente otorgados a usted en este EULA.\n\nNo puede modificar, realizar ingeniería inversa, descompilar o desensamblar $appName. Esta licencia es válida hasta que sea terminada por usted o Bars Opus, Ltd. Sus derechos bajo esta licencia terminarán automáticamente sin previo aviso si incumple cualquier término.\n\nTodos los derechos de propiedad intelectual sobre $appName son propiedad de Bars Opus, Ltd. Este EULA se rige por las leyes de Inglaterra y Gales.\n\nPara preguntas sobre este EULA, por favor contacte: $supportEmail.';
  }

  @override
  String get eulaFooter => 'Al aceptar, usted reconoce que ha leído y comprendido este Acuerdo de Licencia de Usuario Final.';

  @override
  String get privacyPolicyTitle => 'Política de Privacidad';

  @override
  String privacyPolicyContent(String appName) {
    return 'Esta Política de Privacidad explica cómo Bars Opus, Ltd. (\"nosotros\", \"nuestro\") recopila, utiliza y protege su información cuando usa $appName.\n\nRecopilamos información que usted proporciona directamente, como cuando crea una cuenta, completa su perfil o contacta al soporte. Recopilamos automáticamente cierta información sobre su dispositivo y cómo usa $appName. Usamos cookies y tecnologías de seguimiento similares para rastrear la actividad y almacenar cierta información.\n\nUsamos la información que recopilamos para proporcionar, mantener y mejorar $appName. Podemos compartir su información con proveedores de servicios de terceros que realizan servicios en nuestro nombre. Podemos divulgar su información si lo requiere la ley o para proteger nuestros derechos y seguridad.\n\nUsted tiene derecho a acceder, corregir o eliminar su información personal. Implementamos medidas técnicas y organizativas apropiadas para proteger su información. Podemos actualizar esta Política de Privacidad de vez en cuando. Le notificaremos cualquier cambio.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return 'Política de Privacidad de $appName - Última actualización: $currentDateString';
  }

  @override
  String get termsTitle => 'Términos de Servicio';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'Estos Términos de Servicio (\"Términos\") rigen su acceso y uso de $appName. Al acceder o usar $appName, usted acepta estar sujeto a estos Términos.\n\nDebe tener al menos 13 años para usar $appName. Usted es responsable de proteger sus credenciales de cuenta y de todas las actividades bajo su cuenta. No puede usar $appName para ningún propósito ilegal o no autorizado.\n\nNos reservamos el derecho de modificar, suspender o descontinuar $appName en cualquier momento. Todo el contenido incluido en $appName es propiedad de Bars Opus, Ltd. o sus licenciantes.\n\nPodemos terminar o suspender su acceso a $appName inmediatamente si viola estos Términos. Estos Términos se regirán e interpretarán de acuerdo con las leyes de Inglaterra y Gales.\n\nPara cualquier pregunta sobre estos Términos, por favor contáctenos en $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Acuerdo de Compartición de Datos';

  @override
  String dataSharingContent(String appName) {
    return 'Este Acuerdo de Compartición de Datos describe cómo se puede compartir su información cuando usa las funciones sociales de $appName.\n\nCuando se conecta con amigos en $appName, ciertos datos de actividad pueden ser visibles para ellos. Los datos de actividad compartidos pueden incluir duración del entrenamiento, calorías quemadas, minutos de ejercicio y insignias de logros. Su información de perfil (nombre para mostrar y foto de perfil) es visible para los amigos con los que se conecta.\n\nSu dirección de correo electrónico e información de contacto permanecen privadas y nunca se comparten con otros usuarios. Usted controla qué datos se comparten a través de su configuración de privacidad de $appName. Puede revocar los permisos de compartición en cualquier momento en la configuración de la aplicación.\n\nLos datos compartidos con amigos se cifran durante la transmisión y el almacenamiento. Conservamos los datos compartidos solo el tiempo necesario para proporcionar la funcionalidad de compartición. Las integraciones de terceros pueden tener sus propias prácticas de compartición de datos, que recomendamos revisar.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'La compartición de datos en $appName ayuda a crear una comunidad de apoyo mientras respeta sus elecciones de privacidad.';
  }

  @override
  String get dashboardTitle => 'Panel de Control';

  @override
  String get dashboardSubtitle => 'Gestiona las actividades de tu tienda de manera eficiente';

  @override
  String get dashboardSectionTitle => 'Panel de Control';

  @override
  String get dashboardSectionSubtitle => 'Resumen del rendimiento y métricas clave de tu tienda';

  @override
  String get dashboardPayoutTitle => 'Solicitar Pago';

  @override
  String get dashboardPayoutContent => 'Los propietarios de tiendas pueden solicitar pagos semanales. Navega a la sección de Ganancias, revisa tu saldo y envía una solicitud de pago. Los fondos generalmente se procesan en 3-5 días hábiles.';

  @override
  String get dashboardAnalyticsTitle => 'Panel de Análisis';

  @override
  String get dashboardAnalyticsContent => 'Rastrea el rendimiento de tu tienda con análisis en tiempo real. Monitorea tendencias de ventas, compromiso del cliente y niveles de inventario a través de gráficos interactivos e informes.';

  @override
  String get dashboardScreenshotTitle => 'Vista General del Panel';

  @override
  String get dashboardScreenshotContent => 'El panel principal proporciona una vista integral de las métricas clave de tu tienda, actividades recientes y acceso rápido a funciones esenciales.';

  @override
  String get categoryFeatures => 'Características';

  @override
  String get categoryDashboard => 'Panel de Control';

  @override
  String get faqDashboard1Question => '¿Cuándo puedo solicitar un pago?';

  @override
  String get faqDashboard1Answer => 'Puedes solicitar tu pago una vez a la semana, cada sábado. El corte semanal es el viernes a las 11:59 PM. Los pagos se procesan en 3-5 días hábiles.';

  @override
  String get faqDashboard2Question => '¿Dónde solicito mi pago?';

  @override
  String get faqDashboard2Answer => 'Navega a tu panel de control y haz clic en la sección \'Ganancias\'. Desde allí, verás tu saldo actual y un botón \'Solicitar Pago\'. Sigue las indicaciones para completar tu solicitud.';

  @override
  String get profileScreenCantChatWithYourself => 'No puedes chatear contigo mismo';

  @override
  String get profileScreenStartingConversation => 'Iniciando conversación...';

  @override
  String get profileScreenNoActiveSession => 'No hay sesión activa — por favor inicie sesión de nuevo.';

  @override
  String get profileScreenSignInToChatMessage => 'Debe iniciar sesión para enviar un mensaje';

  @override
  String get profileScreenFollowFeatureComingSoon => 'La función de seguimiento próximamente';

  @override
  String get profileScreenEnterBioPlaceholder => 'Ingrese una biografía para que la gente lo conozca';

  @override
  String get profileScreenNoBioYet => 'Sin biografía aún';

  @override
  String get profileScreenErrorLoadingProfileBody => 'No se pudo cargar el perfil. Verifique su conexión a internet e intente de nuevo.';

  @override
  String get profileScreenLoadingNotifications => 'Cargando...';

  @override
  String get profileHeaderBookingsStatLabel => 'Reservas';

  @override
  String get profileHeaderOrdersStatLabel => 'Pedidos';

  @override
  String get profileHeaderEditProfileButton => 'Editar perfil';

  @override
  String get profileHeaderMessageButton => 'Mensaje';

  @override
  String get editableProfileAvatarTakePhoto => 'Tomar una foto';

  @override
  String get editableProfileAvatarChooseGallery => 'Elegir de la galería';

  @override
  String get editProfileScreenAccountTypeLabel => 'Tipo de cuenta';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Selecciona cómo deseas usar esta aplicación. Esto determina qué características están disponibles para ti.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Actualizando tipo de cuenta...';

  @override
  String get editProfileScreenPleaseLogIn => 'Por favor inicie sesión';

  @override
  String get editProfileScreenNameLabel => 'Nombre';

  @override
  String get editProfileScreenNameHint => 'Ingrese su nombre';

  @override
  String get editProfileScreenUsernameLabel => 'Nombre de usuario';

  @override
  String get editProfileScreenUsernameHint => 'Ingrese el nombre de usuario';

  @override
  String get editProfileScreenBioLabel => 'Biografía';

  @override
  String get editProfileScreenBioHint => 'Cuéntanos algo sobre ti';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Editar perfil de trabajo';

  @override
  String get profileTabsAppointments => 'Citas';

  @override
  String get profileTabsBuys => 'Compras';

  @override
  String get profileTabsSaves => 'Guardados';

  @override
  String get searchScreenSearchHint => 'Busca tiendas, profesionales, productos...';

  @override
  String get searchScreenNoResultsFound => 'No se encontraron resultados';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'No se encontraron $category';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Se buscó: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Algo salió mal';

  @override
  String get searchAppBarSearchHint => 'Buscar...';

  @override
  String get searchSuggestionsHint => 'Busca tiendas, profesionales de servicios a domicilio o productos de cabello para comprar';

  @override
  String get searchSuggestionsRecentSearches => 'Búsquedas recientes';

  @override
  String get searchSuggestionsClearAll => 'Borrar todo';

  @override
  String get searchEmptyStateNoResults => 'No se encontraron resultados';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'No pudimos encontrar nada para \"$query\"';
  }

  @override
  String get searchEmptyStateTryThese => 'Intenta con estos:';

  @override
  String get searchResultsShopsHeader => 'Tiendas';

  @override
  String get searchResultsSeeAll => 'Ver todos';

  @override
  String searchResultsTitle(String category) {
    return 'Resultados de $category';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Buscando \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Intenta con palabras clave diferentes o elimina filtros';

  @override
  String get searchResultsSomethingWentWrong => 'Algo salió mal';

  @override
  String nearYouShopsTitle(int km) {
    return 'Cerca de ti\ndenro de ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Tiendas ubicadas dentro de $km km de tu ubicación actual, mostradas de la más cercana a la más lejana. Simplemente establece tu ubicación una vez, y te mostraremos qué hay cerca—ya sea en casa, en el trabajo o explorando un barrio nuevo. Útil para reservas de último minuto o cuando prefieres caminar.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'No se encontraron tiendas cercanas';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'No se encontraron tiendas $luxury cercanas';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'Las tiendas en $location se mostrarían aquí una vez que estén disponibles';
  }

  @override
  String get premiumShopsScreenTitle => 'Tiendas Premium';

  @override
  String get premiumShopsEmpty => 'No se encontraron tiendas premium';

  @override
  String get premiumShopsHorizontalTitle => 'Tiendas Premium\npara looks premium';

  @override
  String get premiumShopsHorizontalBody => 'Salones y spas de lujo cuidadosamente seleccionados que ofrecen experiencias lujosas. Estas tiendas se clasifican como Lujo o Ultra Lujo según sus servicios, precios y reseñas de clientes. Perfecto cuando buscas ese toque extra de elegancia.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'No hay tiendas premium disponibles';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'No hay tiendas premium $luxury disponibles';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'Las tiendas se mostrarían aquí una vez que estén disponibles';

  @override
  String get topRatedShopsHorizontalTitle => 'Mejor valoradas';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Mejor valoradas \nen $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Tiendas con las calificaciones más altas de clientes (4.5+ estrellas) y muchas reseñas. Estos son los favoritos de nuestra comunidad—elogiados constantemente por calidad, servicio y profesionalismo. Un excelente lugar para empezar si buscas opciones confiables y aprobadas por la multitud.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'No hay tiendas mejor valoradas disponibles';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'No hay tiendas premium $luxury disponibles';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'Las tiendas se mostrarían aquí una vez que estén disponibles';

  @override
  String get topRatedShopsScreenTitle => 'Tiendas Mejor Valoradas';

  @override
  String get topRatedShopsEmpty => 'No se encontraron tiendas mejor valoradas';

  @override
  String get nearYouFreelancersScreenTitle => 'Freelancers cerca de ti';

  @override
  String get nearYouFreelancersEmpty => 'No se encontraron freelancers cercanos';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Intenta expandir tu área de búsqueda o cambia tu ubicación';

  @override
  String get topRatedFreelancersScreenTitle => 'Freelancers mejor valorados';

  @override
  String get topRatedFreelancersEmpty => 'No se encontraron freelancers mejor valorados';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Intenta ajustar tu área de búsqueda';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Mejor valorados \nen $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Profesionales de alta calidad cuidadosamente seleccionados que ofrecen experiencias lujosas. Estos freelancers se clasifican como mejor valorados según la calidad de su trabajo, precios y reseñas de clientes. Perfecto para ese toque extra de excelencia.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freelancers Cerca de Ti en $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Profesionales calificados ubicados cerca de ti. Estos freelancers están disponibles para reservas rápidas y ofrecen servicio local conveniente. Perfecto cuando buscas confiabilidad y proximidad.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'No hay freelancers mejor valorados disponibles';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'Los freelancers se mostrarían aquí una vez que estén disponibles';

  @override
  String get shopNoLocationSetTitle => 'Establece tu ubicación para descubrir';

  @override
  String get shopNoLocationSetContent => 'Establece tu ubicación para descubrir tiendas premium y mejor valoradas cerca de ti.';

  @override
  String get providerTypeShops => 'Tiendas';

  @override
  String get providerTypeFreelancers => 'Freelancers';

  @override
  String get providerTypeBuy => 'Comprar';

  @override
  String get luxuryLevelChipsAll => 'Todas';

  @override
  String get searchRadiusSliderTitle => 'Radio de exploración';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Mostrando resultados dentro de ${km}km de tu ubicación';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'La contraseña debe tener como máximo $max caracteres';
  }

  @override
  String get validationPasswordRepeatingChars => 'La contraseña contiene demasiados caracteres repetidos';

  @override
  String get validationPasswordSequential => 'La contraseña contiene caracteres secuenciales';

  @override
  String validationPhoneDigits(int digits) {
    return 'El número de teléfono debe tener $digits dígitos';
  }

  @override
  String get validationPhoneUK => 'Número de teléfono británico inválido';

  @override
  String validationUrlScheme(String schemes) {
    return 'La URL debe comenzar con $schemes';
  }

  @override
  String get validationUrlDomain => 'Nombre de dominio inválido';

  @override
  String get validationUrlPublicAddress => 'La URL debe apuntar a una dirección pública';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field debe tener como máximo $max caracteres';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field no puede contener guiones o espacios consecutivos';
  }

  @override
  String get validationCreditCardFormat => 'Por favor ingresa un número de tarjeta de crédito válido';

  @override
  String get validationCreditCardInvalid => 'Número de tarjeta de crédito inválido';

  @override
  String get validationDatePastNotAllowed => 'La fecha no puede ser en el pasado';

  @override
  String get validationPostalCodeZip => 'Por favor ingresa un código postal válido (ej. 12345 o 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Por favor ingresa un código postal canadiense válido (ej. A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Por favor ingresa un código postal válido';

  @override
  String get validationSSNFormat => 'Por favor ingresa un SSN válido (ej. 123-45-6789)';

  @override
  String get validationSSNInvalid => 'SSN inválido';

  @override
  String get validationEmailTooLong => 'El correo electrónico es demasiado largo (máx. 254 caracteres)';

  @override
  String get validationEmailLocalPartTooLong => 'La parte local del correo electrónico es demasiado larga';

  @override
  String get categoriesAll => 'Todos';

  @override
  String get categoriesSalon => 'Salones';

  @override
  String get categoriesBarbershop => 'Barberías';

  @override
  String get categoriesSpa => 'Spas';

  @override
  String get categoriesNailSalon => 'Salones de Uñas';

  @override
  String get categoriesLashStudio => 'Estudios de Pestañas';

  @override
  String get categoriesWaxing => 'Depilación';

  @override
  String get categoriesMassage => 'Masaje';

  @override
  String get categoriesMakeup => 'Maquillaje';

  @override
  String get categoriesSkincare => 'Cuidado de la Piel';

  @override
  String get luxuryLevelModerate => 'Moderado';

  @override
  String get luxuryLevelLuxury => 'Lujo';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Lujo';

  @override
  String get flow_continue => 'Continue';

  @override
  String get flow_close => 'Close';

  @override
  String get flow_back => 'Back';

  @override
  String flow_listTwo(String first, String second) {
    return '$first and $second';
  }

  @override
  String get flow_countryUk => 'the UK';

  @override
  String get flow_countryUs => 'the US';

  @override
  String get flow_welcomeTitle => 'Love, dating and you, in one calm place.';

  @override
  String get flow_pathRelationshipTitle => 'In a relationship';

  @override
  String get flow_pathRelationshipLine => 'A private space for you and your partner.';

  @override
  String get flow_pathDatingTitle => 'Single and open to dating';

  @override
  String get flow_pathDatingLine => 'A few introductions a day. Only when it\'s mutual.';

  @override
  String get flow_pathJustMeTitle => 'Just for me';

  @override
  String get flow_pathJustMeLine => 'Your journal, quizzes and Healing.';

  @override
  String flow_welcomeCardSemantics(String title, String line) {
    return '$title. $line Opens a preview.';
  }

  @override
  String get flow_welcomeGetStarted => 'Get started';

  @override
  String get flow_welcomeHaveAccount => 'I already have an account';

  @override
  String get flow_welcomeHaveInvite => 'I have an invite';

  @override
  String get flow_welcomeReadOpinions => 'Read Opinions first';

  @override
  String get flow_welcomeFooter => 'Attune is for adults (18+) and uses your phone number to sign in.';

  @override
  String get flow_linkTerms => 'Terms';

  @override
  String get flow_linkPrivacy => 'Privacy';

  @override
  String get flow_previewRelationshipTitle => 'A space for the two of you';

  @override
  String get flow_previewRelationshipLine1 => 'Chat, plans and memories only you two can see.';

  @override
  String get flow_previewRelationshipLine2 => 'Your journal stays yours. Your partner never sees it.';

  @override
  String get flow_previewRelationshipLine3 => 'Invite your partner with a link or a code.';

  @override
  String get flow_previewDatingTitle => 'Introductions, not swiping';

  @override
  String get flow_previewDatingLine1 => 'Up to 3 introductions a day, chosen for what you both want.';

  @override
  String get flow_previewDatingLine2 => 'A match only when you both say yes.';

  @override
  String get flow_previewDatingLine3 => 'A live video selfie checks your age before your first introduction.';

  @override
  String flow_previewDatingCountries(String countries) {
    return 'Dating is open in $countries. More countries later.';
  }

  @override
  String get flow_previewJustMeTitle => 'A private space for you';

  @override
  String get flow_previewJustMeLine1 => 'A journal only you can read.';

  @override
  String get flow_previewJustMeLine2 => 'Short quizzes about how you connect.';

  @override
  String get flow_previewJustMeLine3 => 'Healing, after a breakup or a loss.';

  @override
  String get flow_previewJustMeLine4 => 'Single, partnered or in between.';

  @override
  String get flow_guestAgeTitle => 'What year were you born?';

  @override
  String get flow_guestAgeHint => 'We ask everyone. It stays on this phone.';

  @override
  String get flow_guestAgeLabel => 'Year';

  @override
  String get flow_guestAgeSemantics => 'Year you were born, 4 digits';

  @override
  String get flow_yearFourDigits => 'Enter the year with 4 digits, like 1994.';

  @override
  String get flow_yearFuture => 'That year is in the future.';

  @override
  String get flow_yearCheck => 'Check the year.';

  @override
  String get flow_ageStopTitle => 'Attune is for adults';

  @override
  String get flow_ageStopBody => 'You need to be 18 or older to use Attune. We haven\'t saved anything you entered.';

  @override
  String get flow_ageStopServerLead => 'We couldn\'t create your account.';

  @override
  String get flow_ageStopYouthLink => 'Support for young people';

  @override
  String get flow_inviteTitle => 'You\'ve been invited to Attune';

  @override
  String get flow_inviteBody => 'Someone invited you to a private space on Attune. Create your account to see who it is and to join.';

  @override
  String get flow_inviteCreate => 'Create an account';

  @override
  String get flow_inviteCodeTitle => 'Enter your invite code';

  @override
  String get flow_inviteCodeLabel => 'Invite code';

  @override
  String get flow_inviteCodeError => 'Codes have 6 letters and numbers. Check it with the person who sent it.';

  @override
  String get flow_tryAgain => 'Try again';

  @override
  String get flow_nameTitle => 'What should we call you?';

  @override
  String get flow_nameHint => 'This is the name your partner sees. Opinions never shows it.';

  @override
  String get flow_nameLabel => 'Your name';

  @override
  String get flow_nameNeedsLetter => 'Add a name with at least one letter.';

  @override
  String get flow_nameTooLong => 'Use 40 characters or fewer.';

  @override
  String get flow_dobTitle => 'What\'s your date of birth?';

  @override
  String get flow_dobHint => 'We only ever show your age, never your birthday.';

  @override
  String flow_dobExample(String example) {
    return 'For example, $example';
  }

  @override
  String get flow_dobDay => 'Day';

  @override
  String get flow_dobMonth => 'Month';

  @override
  String get flow_dobYear => 'Year';

  @override
  String get flow_dobDaySemantics => 'Day of birth';

  @override
  String get flow_dobMonthSemantics => 'Month of birth';

  @override
  String get flow_dobYearSemantics => 'Year of birth';

  @override
  String get flow_dobDayRange => 'Day must be between 1 and 31.';

  @override
  String get flow_dobMonthRange => 'Month must be between 1 and 12.';

  @override
  String get flow_dobYearDigits => 'Year must have 4 digits.';

  @override
  String get flow_dobNoSuchDate => 'That date doesn\'t exist. Check the day and month.';

  @override
  String get flow_dobFuture => 'That date is in the future.';

  @override
  String get flow_dobCheckYear => 'Check the year.';

  @override
  String flow_dobAge(int age) {
    return 'that makes you $age.';
  }

  @override
  String get flow_phoneTitle => 'What\'s your phone number?';

  @override
  String get flow_phoneHint => 'We\'ll text you a code to sign in. We never show your number to anyone.';

  @override
  String get flow_phoneLabel => 'Phone number';

  @override
  String flow_phoneCountrySemantics(String country, String code) {
    return 'Country, $country, $code';
  }

  @override
  String get flow_phoneChooseCountry => 'Choose your country';

  @override
  String get flow_phoneSend => 'Text me a code';

  @override
  String get flow_phoneTerms => 'By continuing you agree to the Terms and Privacy Policy.';

  @override
  String get flow_phoneTooShort => 'Check the number. It looks too short.';

  @override
  String get flow_phoneTooLong => 'Check the number. It looks too long.';

  @override
  String flow_phoneWrongCountry(String country) {
    return 'That doesn\'t look like a $country number. Check the country.';
  }

  @override
  String get flow_sending => 'Sending your code…';

  @override
  String get flow_sendFailed => 'We couldn\'t send a code. Try again or try WhatsApp.';

  @override
  String get flow_sendFailedSms => 'We couldn\'t send a code. Try again.';

  @override
  String flow_tooManyCodes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Too many codes. Try again in $minutes minutes.',
      one: 'Too many codes. Try again in 1 minute.',
    );
    return '$_temp0';
  }

  @override
  String get flow_tooManyTries => 'Too many tries. Try again in a few minutes.';

  @override
  String get flow_accountChecking => 'Checking your account…';

  @override
  String get flow_accountCheckFailedTitle => 'We couldn\'t check your account';

  @override
  String get flow_accountCheckFailedBody => 'Check your connection and try again.';

  @override
  String get flow_phoneUnavailable => 'Phone sign-in is unavailable right now. Please try again later.';

  @override
  String get flow_codeTitle => 'Enter the code';

  @override
  String flow_codeSubtitle(String number) {
    return 'We sent a 6-digit code to $number.';
  }

  @override
  String get flow_codeChangeNumber => 'Wrong number? Change it';

  @override
  String flow_codeResendIn(String time) {
    return 'Send a new code in $time';
  }

  @override
  String get flow_codeResend => 'Send a new code';

  @override
  String get flow_codeNewest => 'Use the newest code.';

  @override
  String get flow_codeSemantics => 'Verification code, 6 digits';

  @override
  String get flow_codeWrong => 'That code didn\'t work. Check it and try again.';

  @override
  String get flow_codeExpired => 'That code has expired. Send a new one.';

  @override
  String get flow_codeAccepted => 'Code accepted';

  @override
  String get flow_codeCheckFailed => 'We couldn\'t check the code right now. Try again.';

  @override
  String get flow_consentTitle => 'Before you start';

  @override
  String get flow_consentUpdatedTitle => 'We\'ve updated our terms';

  @override
  String get flow_consentAdults => 'Attune is for adults. Everyone here is 18 or older.';

  @override
  String get flow_consentAi => 'Some Attune features use AI to give you private suggestions. In a shared space they can read your chat with your partner, and only after you both agree. What it suggests to one of you is never shown to the other.';

  @override
  String get flow_consentData => 'You can download everything you\'ve added, and delete your account, any time.';

  @override
  String get flow_consentTermsLink => 'Terms of use';

  @override
  String get flow_consentPrivacyLink => 'Privacy policy';

  @override
  String get flow_consentAiLink => 'More about AI in Attune';

  @override
  String get flow_consentAgree => 'Agree and continue';

  @override
  String get flow_consentNotNow => 'Not now';

  @override
  String get flow_signupPhoneRequired => 'Phone sign-in is unavailable right now.';

  @override
  String get flow_saveFailed => 'We couldn\'t save that. Try again.';

  @override
  String get flow_noAccountTitle => 'We couldn\'t find an Attune account for this number';

  @override
  String get flow_noAccountBody => 'You can create one now.';

  @override
  String get flow_noAccountCreate => 'Create an account';

  @override
  String get flow_noAccountOtherNumber => 'Use a different number';

  @override
  String flow_welcomeBack(String name) {
    return 'Welcome back, $name.';
  }

  @override
  String get flow_welcomeBackNoName => 'Welcome back.';

  @override
  String get flow_joinTitle => 'Join Attune';

  @override
  String get flow_joinBody => 'A private space for couples, a few introductions a day for singles, and a journal just for you.';

  @override
  String get flow_phoneWhatsApp => 'Send by WhatsApp instead';

  @override
  String flow_whatsAppTitle(String number) {
    return 'Is WhatsApp on $number?';
  }

  @override
  String get flow_whatsAppBody => 'We\'ll send the code to WhatsApp on this number. If WhatsApp is on a different number, we\'ll text you instead.';

  @override
  String get flow_whatsAppYes => 'Yes, send it to WhatsApp';

  @override
  String get flow_whatsAppNo => 'No, text me';

  @override
  String get flow_codeTryWhatsApp => 'Try WhatsApp';

  @override
  String get flow_codeCallMe => 'Call me with the code';

  @override
  String flow_codeCalling(String number) {
    return 'We\'re calling $number now. The code is read out twice.';
  }

  @override
  String get flow_tabMe => 'Me';

  @override
  String get flow_tabSignIn => 'Sign in';

  @override
  String get flow_pathTitle => 'What brings you to Attune?';

  @override
  String get flow_pathJustMeLineFull => 'Your journal, quizzes and Healing. Single, partnered or in between.';

  @override
  String flow_pathNotOpen(String country) {
    return 'Not open in $country yet';
  }

  @override
  String get flow_pathFooter => 'You can change this any time. Your journal and quizzes are yours whichever you choose.';

  @override
  String get flow_pathAlreadyInvited => 'My partner already invited me';

  @override
  String get flow_pathGroupSemantics => 'Choose one of three';

  @override
  String get flow_pathDatingOffline => 'Dating needs a connection. Try again when you\'re online.';

  @override
  String get flow_cancel => 'Cancel';

  @override
  String get flow_cancelInviteTitle => 'Cancel your invite?';

  @override
  String get flow_cancelInviteBody => 'Your invite code will stop working. Your partner won\'t be told.';

  @override
  String flow_cancelInviteBodyNamed(String name) {
    return 'Your invite code will stop working. $name won\'t be told.';
  }

  @override
  String get flow_cancelInviteConfirm => 'Cancel invite and switch';

  @override
  String get flow_cancelInviteKeep => 'Keep invite';

  @override
  String get flow_pauseDatingTitle => 'Inviting a partner pauses Dating';

  @override
  String get flow_pauseDatingBody => 'Your introductions stop and your Dating profile is hidden. Nobody is told.';

  @override
  String get flow_switchOffline => 'You\'re offline. Try again when you\'re connected.';

  @override
  String get flow_dobAddTitle => 'Add your date of birth';

  @override
  String get flow_holdTitle => 'We need to check your account';

  @override
  String get flow_holdBody => 'You can\'t use Attune while we do this. If you think this is a mistake, contact support.';

  @override
  String get flow_holdContact => 'Contact support';

  @override
  String get flow_signOut => 'Sign out';

  @override
  String get flow_updateTitle => 'Update Attune to continue';

  @override
  String get flow_updateBody => 'This version of Attune can\'t finish setting up your account. Update the app from your app store, then open it again.';

  @override
  String get flow_checkOfflineTitle => 'We couldn\'t check your account';

  @override
  String get flow_checkOfflineBody => 'Check your connection, then try again.';

  @override
  String get flow_invitePartnerTitle => 'Invite your partner';

  @override
  String get flow_invitePartnerBody => 'Send a link. When your partner joins, your private space opens.';

  @override
  String get flow_invitePartnerCreate => 'Create my invite';

  @override
  String get flow_invitePartnerLater => 'Invite later';

  @override
  String get flow_invitePartnerDone => 'Done';

  @override
  String get flow_pathOpenSpace => 'You\'re in a shared space. To use Attune another way, end it or pause it first.';

  @override
  String get flow_inviteCodeRefused => 'This code didn\'t work. It may have expired or been used. Ask for a new one.';

  @override
  String get flow_inviteCodeAlreadyIn => 'You\'re already in a shared space, so this invite can\'t be used.';

  @override
  String get flow_inviteCodeOffline => 'We couldn\'t check that code. Try again when you\'re online.';

  @override
  String get flow_ageStopAccountBody => 'You need to be 18 or older to use Attune. Your account is on hold.';

  @override
  String get flow_spaceTitle => 'Your space';

  @override
  String get flow_settingsTooltip => 'Settings';

  @override
  String get flow_spaceJournal => 'Journal';

  @override
  String get flow_spaceJournalLine => 'Notes only you can read';

  @override
  String get flow_spaceQuizzes => 'Quizzes';

  @override
  String get flow_spaceQuizzesLine => 'Short, private, about you';

  @override
  String get flow_spaceHealing => 'Healing';

  @override
  String get flow_spaceHealingLine => 'After a breakup or a loss';

  @override
  String get flow_firstStartHere => 'Start here';

  @override
  String get flow_firstWriteNote => 'Write your first note';

  @override
  String get flow_firstQuiz => 'Take a 3-minute look at how you connect';

  @override
  String get flow_firstSaved => 'Saved, just for you.';

  @override
  String get flow_moreWays => 'More ways to use Attune';

  @override
  String get flow_moreInvite => 'Invite a partner';

  @override
  String get flow_justMeSheetTitle => 'Use Attune just for you?';

  @override
  String get flow_justMeSheetBody => 'Dating will be paused and hidden. Nobody is told. You can delete your Dating profile from Dating settings.';

  @override
  String get flow_justMeSheetSwitch => 'Switch';

  @override
  String get flow_waitWriteNote => 'Write a first note';

  @override
  String get flow_waitQuiz => 'A quiz about you, for you';

  @override
  String get flow_waitReceipts => 'When your partner joins, read receipts start off. You can each turn them on later.';

  @override
  String get flow_inviteMenu => 'Invite options';

  @override
  String get flow_cancelThisInvite => 'Cancel this invite';

  @override
  String get flow_cancelThisInviteTitle => 'Cancel this invite?';

  @override
  String get flow_cancelThisInviteConfirm => 'Cancel invite';

  @override
  String flow_waitReceiptsNamed(String partnerFirstName) {
    return 'When your partner joins, read receipts start off. You and $partnerFirstName can each turn them on later.';
  }

  @override
  String get flow_slotDatingTitle => 'Dating';

  @override
  String get flow_slotDatingBody => 'Up to 3 introductions a day. A match only when you both say yes.';

  @override
  String get flow_slotSetUp => 'Set up Dating';

  @override
  String get flow_slotNotReady => 'Not ready? Use Attune just for me';

  @override
  String flow_slotNotOpenTitle(String country) {
    return 'Dating isn\'t open in $country yet';
  }

  @override
  String flow_slotNotOpenBody(String countries) {
    return 'Dating is open in $countries. We\'re adding countries one at a time.';
  }

  @override
  String flow_slotChangeCountry(String country) {
    return 'Not in $country? Change';
  }

  @override
  String get flow_slotChooseCountry => 'Choose your country';

  @override
  String get flow_slotClosedTitle => 'Dating isn\'t open yet';

  @override
  String get flow_slotClosedBody => 'It opens one country at a time. Your journal, quizzes and Healing are here meanwhile.';

  @override
  String flow_slotGentleWait(String date) {
    return 'Dating opens for you on $date.';
  }

  @override
  String get flow_slotGentleWaitWhy => 'This pause is because your relationship ended here. It isn\'t a judgement about you.';

  @override
  String get flow_slotHealing => 'Healing is here if you want it';

  @override
  String get flow_slotLocked => 'Dating is locked';

  @override
  String get flow_slotLockedLine => 'Enter your Safety PIN to show it';

  @override
  String get flow_lockTitle => 'Dating lock';

  @override
  String get flow_lockSubtitle => 'Ask for your Safety PIN before showing Dating.';

  @override
  String get flow_slotGentleWaitNoDate => 'Dating opens for you after a pause.';

  @override
  String get flow_pushTurnOn => 'Turn on';

  @override
  String get flow_pushAskR2 => 'Get a heads-up when your partner joins';

  @override
  String flow_pushAskR2Named(String name) {
    return 'Get a heads-up when $name joins';
  }

  @override
  String get flow_reminderTitle => 'Remind me to write';

  @override
  String get flow_reminderOff => 'Off';

  @override
  String flow_reminderWhen(String days, String time) {
    return '$days at $time';
  }

  @override
  String get flow_weekdaysMon => 'Mondays';

  @override
  String get flow_weekdaysTue => 'Tuesdays';

  @override
  String get flow_weekdaysWed => 'Wednesdays';

  @override
  String get flow_weekdaysThu => 'Thursdays';

  @override
  String get flow_weekdaysFri => 'Fridays';

  @override
  String get flow_weekdaysSat => 'Saturdays';

  @override
  String get flow_weekdaysSun => 'Sundays';

  @override
  String get flow_weekdayMon => 'Mon';

  @override
  String get flow_weekdayTue => 'Tue';

  @override
  String get flow_weekdayWed => 'Wed';

  @override
  String get flow_weekdayThu => 'Thu';

  @override
  String get flow_weekdayFri => 'Fri';

  @override
  String get flow_weekdaySat => 'Sat';

  @override
  String get flow_weekdaySun => 'Sun';

  @override
  String get flow_reminderSheetTitle => 'When should we remind you?';

  @override
  String get flow_reminderDay => 'Day';

  @override
  String get flow_reminderTime => 'Time';

  @override
  String get flow_reminderChangeTime => 'Change time';

  @override
  String get flow_reminderTurnOn => 'Turn on';

  @override
  String get flow_reminderTurnOff => 'Turn off';

  @override
  String get flow_reminderNeedsPush => 'Reminders need notifications.';

  @override
  String get flow_reminderTurnOnPush => 'Turn on notifications';

  @override
  String get flow_reminderReadFailed => 'We couldn\'t load your reminder. Try again.';

  @override
  String flow_reminderQuietHours(String start, String end) {
    return 'Reminders can be set from $start to $end.';
  }

  @override
  String get flow_howTitle => 'How you use Attune';

  @override
  String get flow_howSubtitle => 'In a relationship, dating, or just for you';

  @override
  String get flow_howFooter => 'Your journal, quizzes and Healing stay yours whichever you choose. Nobody is told when you change this.';

  @override
  String flow_sharedOpenTitle(String name) {
    return 'You\'re in a shared space with $name';
  }

  @override
  String get flow_yourPartner => 'your partner';

  @override
  String get flow_sharedOpenBody => 'To use Attune another way, end it first. Pausing keeps it, read-only, for up to 30 days.';

  @override
  String get flow_sharedPause => 'Pause our shared space';

  @override
  String get flow_sharedEnd => 'End relationship';

  @override
  String get flow_notNow => 'Not now';

  @override
  String get flow_joinAlreadyIn => 'You\'re already in a relationship on Attune. End it first to join a new one.';

  @override
  String get flow_joinNotPossible => 'We couldn\'t link these accounts. If you think this is wrong, contact support.';

  @override
  String get flow_joinOwn => 'This is your own invite. Send it to your partner instead.';

  @override
  String get flow_joinInvalid => 'We couldn\'t find that invite. Check the code with the person who sent it.';

  @override
  String get flow_joinTryLater => 'You\'ve checked a lot of codes. Try again in a little while.';

  @override
  String get flow_inviteErrorSignUp => 'Finish setting up your account first, then try again.';

  @override
  String get flow_inviteErrorCap => 'You already have 3 invites waiting. Cancel one before you send another.';

  @override
  String get flow_inviteErrorAgeRequired => 'Add your date of birth first, then send your invite.';

  @override
  String get flow_inviteErrorTryAgain => 'We couldn\'t make your invite. Try again.';

  @override
  String flow_inviteMsgSimpleOpen(String name) {
    return 'Hi $name, I\'d like us to try Attune together. It\'s a private space just for the two of us.';
  }

  @override
  String get flow_inviteMsgSimpleOpenNoName => 'Hi, I\'d like us to try Attune together. It\'s a private space just for the two of us.';

  @override
  String flow_inviteMsgSimpleGet(String link) {
    return 'Get the app: $link';
  }

  @override
  String flow_inviteMsgCasualOpen(String name) {
    return 'Hey $name! I found an app for couples and thought of us. Private, just you and me.';
  }

  @override
  String get flow_inviteMsgCasualOpenNoName => 'Hey! I found an app for couples and thought of us. Private, just you and me.';

  @override
  String flow_inviteMsgCasualGet(String link) {
    return 'Get it here: $link';
  }

  @override
  String flow_inviteMsgPidginOpen(String name) {
    return '$name, make we try Attune. Na private space for only you and me.';
  }

  @override
  String get flow_inviteMsgPidginOpenNoName => 'Make we try Attune. Na private space for only you and me.';

  @override
  String flow_inviteMsgPidginGet(String link) {
    return 'Download am: $link';
  }

  @override
  String flow_inviteMsgOpenCode(String code) {
    return 'Open Attune → I have an invite → $code';
  }

  @override
  String get flow_inviteMsgFoundMyself => 'I found this myself. I just thought it\'d be nice.';

  @override
  String get flow_inviteCodeServerError => 'Something went wrong on our side. Try again.';

  @override
  String flow_invitePartnerBodyNamed(String name) {
    return 'Send a link. When $name joins, your private space opens.';
  }

  @override
  String get flow_r1NameLabel => 'Their first name (optional)';

  @override
  String get flow_r1NameHelper => 'Used in your message and on this phone only.';

  @override
  String get flow_r1ToneTitle => 'How should it sound?';

  @override
  String get flow_r1ToneGroup => 'Choose one of the message styles';

  @override
  String get flow_r1ToneSimple => 'Simple';

  @override
  String get flow_r1ToneCasual => 'Casual';

  @override
  String get flow_r1TonePidgin => 'Pidgin';

  @override
  String get flow_r1FoundMyselfToggle => 'Add: \'I found this myself. I just thought it\'d be nice.\'';

  @override
  String get flow_r1PreviewTitle => 'What your partner will see';

  @override
  String flow_r1PreviewTitleNamed(String name) {
    return 'What $name will see';
  }

  @override
  String get flow_r1Making => 'Making your invite';

  @override
  String get flow_r1CodePending => '(your code)';

  @override
  String get flow_r1SendWhatsApp => 'Send on WhatsApp';

  @override
  String get flow_r1ShareOther => 'Share another way';

  @override
  String get flow_r1ShowQr => 'Show QR code';

  @override
  String get flow_r1CopyCode => 'Copy code';

  @override
  String get flow_r1CodeCopied => 'Code copied.';

  @override
  String get flow_r1QrTitle => 'Your invite code';

  @override
  String get flow_r1QrSemantics => 'A QR code for your invite link';

  @override
  String flow_inviteCodeSemantics(String code) {
    return 'Invite code $code';
  }

  @override
  String flow_ri3Title(String name) {
    return 'Join $name?';
  }

  @override
  String get flow_ri3TitleUnnamed => 'Join your partner?';

  @override
  String flow_ri3Body(String name) {
    return '$name invited you to a private space on Attune.';
  }

  @override
  String get flow_ri3BodyUnnamed => 'Your partner invited you to a private space on Attune.';

  @override
  String flow_ri3Button(String name) {
    return 'Join $name';
  }

  @override
  String get flow_ri3ButtonUnnamed => 'Join';

  @override
  String get flow_joinOtherWay => 'Not what you expected? Choose another way to use Attune';

  @override
  String get flow_joinEnterAgain => 'Enter the code again';

  @override
  String get flow_joinExpiredTitle => 'This invite has expired.';

  @override
  String flow_joinExpired(String name) {
    return 'Ask $name to send a new one.';
  }

  @override
  String get flow_joinExpiredUnnamed => 'Ask the person who sent it to send a new one.';

  @override
  String flow_joinAskWhatsApp(String name) {
    return 'Ask $name on WhatsApp';
  }

  @override
  String get flow_joinAskWhatsAppUnnamed => 'Ask on WhatsApp';

  @override
  String flow_joinExpiredMessage(String name) {
    return 'Hi $name, my Attune invite expired. Could you send me a new one?';
  }

  @override
  String get flow_joinExpiredMessageUnnamed => 'Hi, my Attune invite expired. Could you send me a new one?';

  @override
  String get flow_joinChecking => 'Checking your invite';

  @override
  String flow_linkedTitle(String couple) {
    return 'Welcome, $couple';
  }

  @override
  String flow_linkedBody(String name) {
    return 'Your private space with $name is open.';
  }

  @override
  String get flow_linkedBodyUnnamed => 'Your private space with your partner is open.';

  @override
  String flow_pushAskR4(String name) {
    return 'Get notified when $name messages you';
  }

  @override
  String get flow_pushAskR4Unnamed => 'Get notified when your partner messages you';

  @override
  String get flow_inviteErrorNotPossible => 'We couldn\'t make your invite. If you think this is wrong, contact support.';

  @override
  String get flow_guideWaitLine => 'We\'ll suggest a private reflection space if this takes a little while.';

  @override
  String get flow_guideReflectTitle => 'A private space while you wait';

  @override
  String get flow_guideReflectBody => 'Your reflections stay private to you.';

  @override
  String get flow_guideOpenJournal => 'Open your journal';

  @override
  String get flow_guideWeekTitle => 'It\'s been a week';

  @override
  String flow_guideWeekBody(String name) {
    return 'Your invite to $name has run its week. What would you like to do?';
  }

  @override
  String get flow_guideWeekBodyUnnamed => 'Your invite to your partner has run its week. What would you like to do?';

  @override
  String get flow_guideKeepWaiting => 'Keep waiting';

  @override
  String get flow_guideSendNew => 'Send a new invite';

  @override
  String get flow_guideSendNewHelper => 'Send it to the same number or a different one.';

  @override
  String get flow_guideOnMyOwn => 'Use Attune on my own for now';

  @override
  String flow_day30(String name) {
    return 'Want to send $name a new invite?';
  }

  @override
  String get flow_day30Unnamed => 'Want to send your partner a new invite?';

  @override
  String get flow_day30Dismiss => 'Dismiss';

  @override
  String get flow_r3SendAgain => 'Send again';

  @override
  String flow_invitePartnerNamed(String name) {
    return 'Invite $name';
  }

  @override
  String get aboutUs_title => 'About us';

  @override
  String aboutUs_step(int step, int total) {
    return '$step of $total';
  }

  @override
  String aboutUs_stepSemantics(int step, int total) {
    return 'Question $step of $total';
  }

  @override
  String get aboutUs_skip => 'Skip';

  @override
  String get aboutUs_done => 'Done';

  @override
  String get aboutUs_save => 'Save';

  @override
  String get aboutUs_moreAbout => 'More about this';

  @override
  String get aboutUs_moreAboutBody => 'Either of you can change these. It\'s never used to score or type you.';

  @override
  String aboutUs_moreAboutDraft(String name) {
    return 'Before $name joins, your answers are a draft only you can see. When $name joins, your answers become your shared About us.';
  }

  @override
  String get aboutUs_moreAboutDraftUnnamed => 'Before your partner joins, your answers are a draft only you can see. When your partner joins, your answers become your shared About us.';

  @override
  String get aboutUs_stageQuestion => 'How would you describe where you two are?';

  @override
  String get aboutUs_stageDating => 'Dating';

  @override
  String get aboutUs_stageEngaged => 'Engaged';

  @override
  String get aboutUs_stageMarried => 'Married';

  @override
  String get aboutUs_stageOther => 'Something else';

  @override
  String get aboutUs_stageEngagedHelper => 'Planning to marry, including after the knocking and before the wedding.';

  @override
  String get aboutUs_stageMarriedHelper => 'Any kind of marriage: customary, religious or civil.';

  @override
  String get aboutUs_stageWordsLabel => 'In your own words';

  @override
  String get aboutUs_stageWhy => 'So what Attune suggests fits you two. Either of you can change this. It\'s never used to score or type you.';

  @override
  String get aboutUs_sinceQuestion => 'When did you two get together?';

  @override
  String aboutUs_sinceHelper(String couple) {
    return 'Use whichever date feels right to $couple.';
  }

  @override
  String get aboutUs_sinceWhy => 'So we can remember your anniversary with you, if you\'d like.';

  @override
  String get aboutUs_monthLabel => 'Month';

  @override
  String get aboutUs_yearLabel => 'Year';

  @override
  String get aboutUs_dayLabel => 'Day';

  @override
  String get aboutUs_monthOptional => 'Month (optional)';

  @override
  String get aboutUs_dayOptional => 'Day (optional)';

  @override
  String get aboutUs_notSure => 'Not sure';

  @override
  String get aboutUs_sinceAddDay => 'Add the day';

  @override
  String get aboutUs_sinceNoMonth => 'Not sure of the month';

  @override
  String get aboutUs_sinceSuggestions => 'Suggested dates';

  @override
  String get aboutUs_errorFuture => 'That date is in the future.';

  @override
  String get aboutUs_errorNoSuchDate => 'Check the day and month.';

  @override
  String get aboutUs_errorNeedsYear => 'Choose a year.';

  @override
  String get aboutUs_marryQuestion => 'What year did you marry?';

  @override
  String aboutUs_ceremonyN(int n) {
    return 'Ceremony $n';
  }

  @override
  String get aboutUs_ceremonyLabelGroup => 'What kind of ceremony? (optional)';

  @override
  String get aboutUs_labelCustomary => 'Customary';

  @override
  String get aboutUs_labelChurch => 'Church';

  @override
  String get aboutUs_labelMosque => 'Mosque';

  @override
  String get aboutUs_labelCivil => 'Civil';

  @override
  String get aboutUs_labelOther => 'Other';

  @override
  String get aboutUs_addCeremony => 'Had more than one ceremony? Add another';

  @override
  String get aboutUs_removeCeremony => 'Remove this ceremony';

  @override
  String get aboutUs_livingQuestion => 'Where do you two live?';

  @override
  String get aboutUs_livingTogether => 'Together';

  @override
  String get aboutUs_livingApartNearby => 'Apart, nearby';

  @override
  String get aboutUs_livingLongDistance => 'Long distance';

  @override
  String get aboutUs_livingWhy => 'So plans, maps and reminders fit how you live.';

  @override
  String get aboutUs_childrenQuestion => 'Are there children in your life together?';

  @override
  String get aboutUs_childrenNo => 'No';

  @override
  String get aboutUs_childrenYes => 'Yes';

  @override
  String get aboutUs_childrenExpecting => 'We\'re expecting';

  @override
  String get aboutUs_childrenPreferNot => 'Prefer not to say';

  @override
  String get aboutUs_childrenAges => 'Their ages (optional)';

  @override
  String get aboutUs_bandUnder2 => 'Under 2';

  @override
  String get aboutUs_band2to5 => '2–5';

  @override
  String get aboutUs_band6to12 => '6–12';

  @override
  String get aboutUs_band13to17 => '13–17';

  @override
  String get aboutUs_band18plus => '18+';

  @override
  String get aboutUs_childrenWhy => 'So ideas and reminders suit your family.';

  @override
  String get aboutUs_anniversaryQuestion => 'Remember your anniversary?';

  @override
  String get aboutUs_anniversaryNo => 'No, thanks';

  @override
  String get aboutUs_anniversaryTogether => 'The day you got together';

  @override
  String aboutUs_anniversaryCeremony(String label, String year) {
    return '$label ceremony, $year';
  }

  @override
  String aboutUs_anniversaryCeremonyPlain(String year) {
    return 'Ceremony, $year';
  }

  @override
  String get aboutUs_anniversaryWhatDay => 'What day was it?';

  @override
  String get aboutUs_rowSince => 'Together since';

  @override
  String get aboutUs_rowStage => 'Where you are';

  @override
  String get aboutUs_rowCeremonies => 'Ceremonies';

  @override
  String get aboutUs_rowLiving => 'Where you live';

  @override
  String get aboutUs_rowChildren => 'Children';

  @override
  String get aboutUs_rowAnniversary => 'Anniversary';

  @override
  String get aboutUs_notAnswered => 'Not answered yet';

  @override
  String aboutUs_childrenYesBands(String bands) {
    return 'Yes ($bands)';
  }

  @override
  String get aboutUs_anniversaryOff => 'Off';

  @override
  String aboutUs_ceremonyLine(String label, String year) {
    return '$label, $year';
  }

  @override
  String aboutUs_changedBy(String name) {
    return 'Changed by $name';
  }

  @override
  String get aboutUs_changedByYou => 'Changed by you';

  @override
  String get aboutUs_changedByPartner => 'Changed by your partner';

  @override
  String get aboutUs_footer => 'Either of you can change these. It\'s never used to score or type you.';

  @override
  String aboutUs_readOnlyUntil(String date) {
    return 'You can read this until $date.';
  }

  @override
  String get aboutUs_pendingSync => 'Saved on this phone. It will be shared when you\'re back online.';

  @override
  String get aboutUs_loadFailed => 'We couldn\'t load About us. Check your connection and try again.';

  @override
  String get aboutUs_answerQuestions => 'Answer a few questions';

  @override
  String get aboutUs_rowEditHint => 'Change';

  @override
  String get aboutUs_errorAnniversaryNeedsDay => 'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.';

  @override
  String get aboutUs_errorReadOnly => 'About us can\'t be changed right now.';

  @override
  String get aboutUs_errorWordsTooLong => 'Use 40 characters or fewer.';

  @override
  String get aboutUs_cardTitle => 'About us';

  @override
  String aboutUs_cardBody(String name) {
    return 'A few easy questions about you two. Skip any of them. $name sees your answers after joining.';
  }

  @override
  String get aboutUs_cardBodyUnnamed => 'A few easy questions about you two. Skip any of them. Your partner sees your answers after joining.';

  @override
  String get aboutUs_settingsSubtitle => 'When you got together, where you live and more';

  @override
  String get aboutUs_reminderFollows => 'This reminder follows About us';

  @override
  String get aboutUs_reminderChange => 'Change in About us';

  @override
  String get aboutUs_reminderStopTitle => 'Your anniversary reminder will stop';

  @override
  String get aboutUs_reminderStopBody => 'It follows this ceremony\'s date. It can follow the day you got together instead.';

  @override
  String get aboutUs_reminderStopOff => 'Turn it off';

  @override
  String get aboutUs_sinceHelperUnnamed => 'Use whichever date feels right.';

  @override
  String get aboutUs_reminderOffline => 'We couldn\'t check this reminder. Check your connection and try again.';

  @override
  String get aboutUs_reminderTimes => 'Reminder times and note';

  @override
  String get aboutUs_reminderLocked => 'Its date, title and type follow About us.';

  @override
  String get aboutUs_anniversaryHandMade => 'You already have an anniversary reminder, so we won\'t add another.';

  @override
  String get flow_dormantTitle => 'Welcome to Attune';

  @override
  String get flow_dormantBody => 'Let\'s get you set up.';

  @override
  String get flow_dormantNew => 'I\'m new to Attune';

  @override
  String get flow_dormantUsedBefore => 'Used Attune before on this number? Contact support';

  @override
  String get flow_dormantFailed => 'We couldn\'t reach Attune. Check your connection and try again.';

  @override
  String get flow_dormantTryLater => 'Too many tries. Try again in an hour.';

  @override
  String get flow_dormantExpired => 'That took too long. Enter your number again.';

  @override
  String get flow_freshStartTitle => 'One more code to finish';

  @override
  String flow_freshStartBody(String phone) {
    return 'We\'ll send a new code to $phone.';
  }

  @override
  String get flow_freshStartSend => 'Send code';

  @override
  String get flow_dobSettingsTitle => 'Date of birth';

  @override
  String get flow_dobSettingsSubtitle => 'Only your age is shown, never the date';

  @override
  String flow_dobSettingsAge(int age) {
    return 'Your age: $age';
  }

  @override
  String get flow_dobSettingsNoAge => 'We don\'t have your date of birth yet.';

  @override
  String flow_dobSettingsFixUntil(String date) {
    return 'If it\'s wrong, you can fix it once, until $date.';
  }

  @override
  String get flow_dobSettingsContact => 'To change this, contact support.';

  @override
  String get flow_dobSettingsFix => 'Fix a mistake';

  @override
  String get flow_dobFixTitle => 'Fix your date of birth';

  @override
  String get flow_dobFixSaved => 'Saved.';

  @override
  String get flow_dobSettingsLoadFailed => 'We couldn\'t load this. Check your connection and try again.';

  @override
  String get support_childReportTitle => 'Report a concern about a child';

  @override
  String get support_childReportSubtitle => 'A person on our team reads every report';

  @override
  String get support_childReportBody => 'Tell us what you saw and where. A person on our team reads every report. If a child is in danger right now, call your local emergency number.';

  @override
  String get support_childReportWhere => 'Where did you see it?';

  @override
  String get support_childReportChat => 'Chat';

  @override
  String get support_childReportStories => 'Stories';

  @override
  String get support_childReportOpinions => 'Opinions';

  @override
  String get support_childReportDating => 'Dating';

  @override
  String get support_childReportElsewhere => 'Somewhere else';

  @override
  String get support_childReportDetails => 'What did you see?';

  @override
  String support_childReportCount(int count, int max) {
    return '$count of $max';
  }

  @override
  String get support_childReportSend => 'Send report';

  @override
  String get support_childReportThanks => 'Thank you. We\'ve received your report.';

  @override
  String support_childReportLimit(String email) {
    return 'You\'ve sent 5 reports today. To tell us more, email $email.';
  }

  @override
  String get support_childReportFailed => 'We couldn\'t send this. Check your connection and try again.';

  @override
  String get support_childReportDone => 'Done';

  @override
  String get support_childReportTooLong => 'This is too long. Keep it to 2,000 characters or fewer.';

  @override
  String support_childReportInvalid(String email) {
    return 'We couldn\'t send this as written. Make it shorter and try again, or email $email.';
  }

  @override
  String get support_resourcesTitle => 'Support resources';

  @override
  String get support_resourcesIntro => 'If something does not feel safe, these contacts and planning resources may be useful.';

  @override
  String get support_resourcesNoEmergencyService => 'Attune cannot assess an emergency or contact help for you.';

  @override
  String get support_quickExit => 'Quick exit';

  @override
  String get support_quickExitBody => 'Tap to exit the app and show a neutral screen.';

  @override
  String get support_exitNow => 'Exit now';

  @override
  String get support_notNow => 'Not relevant right now';

  @override
  String support_helpFor(String country) {
    return 'Help for $country';
  }

  @override
  String get support_changeCountry => 'Change';

  @override
  String support_changeCountryLabel(String country) {
    return 'Change country. Now showing $country';
  }

  @override
  String get support_chooseCountry => 'Choose your country to see help near you.';

  @override
  String get support_chooseCountryButton => 'Choose a country';

  @override
  String get support_loading => 'Looking for help near you';

  @override
  String get support_emergencyHeading => 'In an emergency';

  @override
  String get support_anywhereHeading => 'Anywhere in the world';

  @override
  String get support_categoryEmergency => 'Emergency';

  @override
  String get support_categoryDv => 'Domestic abuse';

  @override
  String get support_categoryCrisis => 'Someone to talk to now';

  @override
  String get support_categorySexualAssault => 'Sexual assault';

  @override
  String get support_categorySextortion => 'Threats to share images';

  @override
  String get support_categoryChildSafety => 'A child at risk';

  @override
  String get support_categoryYouth => 'For young people';

  @override
  String get support_categoryLgbtqLegal => 'LGBTQ+ and legal help';

  @override
  String get support_categoryGrief => 'Grief';

  @override
  String get support_categoryPerinatal => 'Pregnancy and after birth';

  @override
  String get support_categoryAddiction => 'Alcohol, drugs and gambling';

  @override
  String get support_categoryFinancialControl => 'Money and control';

  @override
  String get support_notPolice => 'Not the police';

  @override
  String get support_police => 'Police';

  @override
  String support_call(String number) {
    return 'Call $number';
  }

  @override
  String support_text(String number) {
    return 'Text $number';
  }

  @override
  String get support_whatsapp => 'WhatsApp';

  @override
  String get support_website => 'Website';

  @override
  String support_callConfirmTitle(String number) {
    return 'Call $number?';
  }

  @override
  String get support_callConfirmBody => 'Calls may show in your phone\'s call history.';

  @override
  String get support_callConfirmCall => 'Call';

  @override
  String support_textConfirmTitle(String number) {
    return 'Text $number?';
  }

  @override
  String get support_textConfirmBody => 'Messages may stay on your phone.';

  @override
  String support_linkConfirmTitle(String site) {
    return 'Open $site?';
  }

  @override
  String get support_linkConfirmBody => 'It may show in your browser history.';

  @override
  String get support_open => 'Open';

  @override
  String get support_cancel => 'Cancel';

  @override
  String support_unsupported(String country) {
    return 'We don\'t have a checked list for $country yet.';
  }

  @override
  String support_noFocusList(String country) {
    return 'We don\'t have a checked list for this in $country yet.';
  }

  @override
  String get support_findHelpline => 'Find a helpline';

  @override
  String get support_localEmergency => 'In an emergency, call your local emergency number.';

  @override
  String get support_griefTitle => 'Grief support';

  @override
  String get support_youthTitle => 'Support for young people';

  @override
  String get support_writeInJournal => 'Write about it in your journal';

  @override
  String get support_settingsTitle => 'Find support';

  @override
  String get support_settingsSubtitle => 'Helplines for where you are';

  @override
  String get support_cannotOpen => 'That didn\'t open here. Try it from another phone or computer.';

  @override
  String get flow_healingChoiceTitle => 'What happened?';

  @override
  String get flow_healingBreakup => 'A breakup';

  @override
  String get flow_healingLoss => 'Someone I love died';

  @override
  String get support_whatsappConfirmBody => 'The chat may stay in WhatsApp on your phone.';

  @override
  String get support_back => 'Back';
}
