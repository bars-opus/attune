// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'Nano Embryo';

  @override
  String get appDescription => 'Seu aplicativo inovador';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonLogin => 'Entrar';

  @override
  String get commonLogout => 'Sair';

  @override
  String get commonDone => 'Concluído';

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonAccept => 'Aceitar';

  @override
  String get commonReject => 'Rejeitar';

  @override
  String get introGetStarted => 'Começar';

  @override
  String get actionsBlock => 'Bloquear usuário';

  @override
  String get actionsReport => 'Denunciar usuário';

  @override
  String get actionsSend => 'Enviar para o chat';

  @override
  String get actionsShare => 'Compartilhar';

  @override
  String get actionsCopy => 'Copiar link';

  @override
  String get appInfoVersion => 'Versão';

  @override
  String get appInfoReleased => 'Lançado';

  @override
  String get appInfoPackageName => 'Nome do Pacote';

  @override
  String get appInfoDeveloper => 'Nome do Desenvolvedor';

  @override
  String get appInfoSupportEmail => 'Email de Suporte';

  @override
  String get appInfoTechnicalDetails => 'Detalhes Técnicos';

  @override
  String get appInfoBundleID => 'ID do Pacote';

  @override
  String get appInfoBuildVersion => 'Versão da Compilação';

  @override
  String get appInfoBuildNumber => 'Número da Compilação';

  @override
  String get appInfoReleaseDate => 'Data de Lançamento';

  @override
  String get appInfoAppSize => 'Tamanho do App';

  @override
  String appInfoOverview(String appName) {
    return '$appName é um aplicativo móvel moderno construído com segurança robusta e funcionalidade, projetado para fornecer uma experiência de usuário excepcional com arquitetura limpa e otimização de desempenho.';
  }

  @override
  String introTitle(String appName) {
    return 'Bem-vindo ao $appName';
  }

  @override
  String get introFeature1Title => 'Veja Seu Progresso';

  @override
  String get introFeature1Description => 'Acompanhe seus marcos de desenvolvimento com análises detalhadas e insights';

  @override
  String get introFeature2Title => 'Explore Modelos';

  @override
  String get introFeature2Description => 'Descubra componentes e telas pré-construídos para desenvolvimento rápido';

  @override
  String get introFeature3Title => 'Comece Rapidamente';

  @override
  String get introFeature3Description => 'Inicie seu projeto com configuração zero e melhores práticas';

  @override
  String get appleSignIn => 'Entrar com Apple';

  @override
  String get googleSignIn => 'Entrar com Google';

  @override
  String get appleRegister => 'Registrar com Apple';

  @override
  String get googleRegister => 'Registrar com Google';

  @override
  String get emailAndPassword => 'Digitar e-mail e senha';

  @override
  String get signInTitle => 'Entrar';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get legalConsentPart1 => 'Por favor, leia os ';

  @override
  String get legalConsentPart2 => 'termos e condições';

  @override
  String legalConsentPart3(String appName) {
    return ' e outros documentos legais que regem o seu uso do $appName.';
  }

  @override
  String get emailTitle => 'E-mail';

  @override
  String get passwordTitle => 'Senha';

  @override
  String get loginEmailLabel => 'Endereço de e-mail';

  @override
  String get loginEmailHint => 'Digite seu e-mail';

  @override
  String get loginPasswordLabel => 'Senha';

  @override
  String get loginPasswordHint => 'Digite sua senha';

  @override
  String get loginForgotPasswordPart1 => 'Esqueceu sua senha? ';

  @override
  String get loginForgotPasswordPart2 => 'Toque aqui';

  @override
  String get loginForgotPasswordPart3 => ' para redefinir sua senha?';

  @override
  String get commonConfirmPasswordLabel => 'Confirmar Senha';

  @override
  String get commonConfirmPasswordHint => 'Por favor, confirme sua senha';

  @override
  String get commonPasswordsDoNotMatch => 'As senhas não correspondem';

  @override
  String get commonPasswordConfirmRequired => 'Por favor, confirme sua senha';

  @override
  String commonFieldIsValid(String field) {
    return '$field é válido';
  }

  @override
  String get commonPleaseWait => 'Aguarde a conclusão da operação atual';

  @override
  String get commonUnexpectedError => 'Ocorreu um erro inesperado. Por favor tente novamente.';

  @override
  String get commonSomethingWentWrong => 'Algo deu errado. Por favor tente novamente.';

  @override
  String get commonEnterEmailAndRetry => 'Por favor digite seu endereço de e-mail e tente novamente';

  @override
  String get commonLearnMore => 'Saiba mais';

  @override
  String get authSignUpVerificationSent => 'E-mail de verificação enviado! Por favor verifique sua caixa de entrada.';

  @override
  String authSignUpFailed(String error) {
    return 'Registro falhou: $error';
  }

  @override
  String get authForgotPasswordTitle => 'Esqueceu sua senha?';

  @override
  String get authForgotPasswordSubtitle => 'Digite seu e-mail e enviaremos um link para redefinir sua senha.';

  @override
  String get authSendResetLink => 'Enviar link de redefinição';

  @override
  String get authBackToSignIn => 'Voltar para login';

  @override
  String get authUsernameScreenTitle => 'Escolha seu nome de usuário';

  @override
  String get authUsernameScreenSubtitle => 'Assim é como os outros te veem. Você pode mudar isto mais tarde.';

  @override
  String get authUsernameLabel => 'Nome de usuário';

  @override
  String get authUsernameHint => 'Digite um nome de usuário';

  @override
  String authUsernameMinLength(int min) {
    return 'O nome de usuário deve ter pelo menos $min caracteres';
  }

  @override
  String authUsernameMaxLength(int max) {
    return 'O nome de usuário deve ter no máximo $max caracteres';
  }

  @override
  String get authUsernameFormatError => 'Apenas letras, números e sublinhados são permitidos';

  @override
  String get authUsernameTaken => 'Este nome de usuário já está sendo usado';

  @override
  String get authUsernameCheckError => 'Não foi possível verificar a disponibilidade. Por favor tente novamente.';

  @override
  String get authUsernameSaveError => 'Não foi possível salvar seu nome de usuário. Por favor tente novamente.';

  @override
  String get authUsernameSavedSuccess => 'Nome de usuário salvo com sucesso!';

  @override
  String get authUpdatePasswordTitle => 'Criar nova senha';

  @override
  String get authUpdatePasswordButton => 'Atualizar senha';

  @override
  String get authUpdatePasswordSuccess => 'Senha atualizada com sucesso. Por favor faça login novamente.';

  @override
  String get authPasswordResetSentTitle => 'Verifique seu e-mail';

  @override
  String get authPasswordResetSentBody => 'Enviamos um link de redefinição de senha para';

  @override
  String get authPasswordResetSentNote => 'Toque no link no e-mail para definir uma nova senha. O link expira em 1 hora.';

  @override
  String get authGuestHello => 'Olá!';

  @override
  String authGuestOverview(String appName) {
    return 'Você está navegando $appName como convidado. Entre com seu número de telefone para começar seu espaço compartilhado com seu parceiro – leva só alguns segundos.';
  }

  @override
  String authIntroTitle(String appName) {
    return 'Bem-vindo a\n$appName';
  }

  @override
  String get authIntroSubtitle => 'Bem-vindo à plataforma que construímos para você. Aproveite e divirta-se – o melhor está esperando.';

  @override
  String get authReadLegalities => 'Ler avisos legais';

  @override
  String get authPasswordRequired => 'Por favor digite sua senha';

  @override
  String get authCreatingAccount => 'Criando conta...';

  @override
  String get authAccountCreatedSuccess => 'Conta criada com sucesso!';

  @override
  String get authCheckEmailToConfirm => 'Por favor verifique seu e-mail para confirmar sua conta';

  @override
  String get authSigningInWithGoogle => 'Entrando com Google...';

  @override
  String authGoogleSignInFailed(String error) {
    return 'Falha ao entrar com Google: $error';
  }

  @override
  String get authAuthenticatingWithApple => 'Autenticando com Apple...';

  @override
  String authAppleSignInFailed(String error) {
    return 'Falha ao entrar com Apple: $error';
  }

  @override
  String get authSendingResetEmail => 'Enviando email de redefinição...';

  @override
  String get authResetEmailSent => 'Email de redefinição enviado. Verifique sua caixa de entrada.';

  @override
  String authPasswordResetFailed(String error) {
    return 'Falha ao redefinir senha: $error';
  }

  @override
  String get authVerifyEmailTitle => 'Verifique seu e-mail';

  @override
  String get authVerifyEmailSubtitle => 'Enviamos um link de confirmação para';

  @override
  String get authVerifyEmailNote => 'Toque no link no e-mail para verificar sua conta e continuar.';

  @override
  String get authConfirmationResent => 'Email de confirmação reenviado. Verifique sua caixa de entrada.';

  @override
  String get authResendFailed => 'Falha ao reenviar o email. Por favor tente novamente.';

  @override
  String get authResendEmailButton => 'Reenviar email de confirmação';

  @override
  String authResendEmailCooldown(int seconds) {
    return 'Reenviar email (${seconds}s)';
  }

  @override
  String get currencySelectorPlaceholder => 'Selecionar moeda';

  @override
  String get currencySelectorNoSelected => 'Nenhuma moeda selecionada';

  @override
  String get currencySelectorTitle => 'Selecionar moeda';

  @override
  String get currencySelectorSearchHint => 'Pesquisar por moeda, código ou bandeira...';

  @override
  String get currencySelectorNoResults => 'Nenhuma moeda encontrada';

  @override
  String get discoverScreenTitle => 'Descobrir';

  @override
  String get discoverSearchHint => 'Pesquisar...';

  @override
  String get discoverAllShopsRegion => 'Todas as lojas em sua região';

  @override
  String get discoverAllFreelancers => 'Todos os freelancers perto de você';

  @override
  String get discoverMarketplaceTitle => 'Mercado';

  @override
  String get discoverMarketplaceSubtitle => 'Compre produtos de beleza com pagamento na entrega';

  @override
  String get discoverBrowseProducts => 'Procurar produtos';

  @override
  String get discoverMyOrders => 'Meus pedidos';

  @override
  String get discoverCartTooltip => 'Carrinho';

  @override
  String get homeScheduleTabLabel => 'Cronograma';

  @override
  String get homeDashboardTabLabel => 'Painel';

  @override
  String get homeMapTabLabel => 'Mapa';

  @override
  String get validationRequired => 'Este campo é obrigatório';

  @override
  String get validationEmailInvalid => 'Digite um endereço de e-mail válido';

  @override
  String validationPasswordLength(int minLength) {
    return 'A senha deve ter pelo menos $minLength caracteres';
  }

  @override
  String get validationPasswordUppercase => 'A senha deve incluir pelo menos uma letra maiúscula';

  @override
  String get loggingInIndicatorText => 'Entrando...';

  @override
  String get loginSuccessful => 'Login bem-sucedido!\nBem-vindo de volta';

  @override
  String get errorLoginFailed => 'Falha no login. Verifique suas credenciais';

  @override
  String get errorNetwork => 'Erro de rede. Verifique sua conexão';

  @override
  String get homeTitle => 'Início';

  @override
  String get profileTitle => 'Perfil';

  @override
  String get chatTitle => 'Chat';

  @override
  String get editProfileNameFieldTitle => 'Nome';

  @override
  String get editProfileNameFieldLabel => 'Nome completo';

  @override
  String get editProfileUserFieldNameTitle => 'Nome de usuário';

  @override
  String get editProfileUsernameFieldLabel => '@nomedeusuario';

  @override
  String get editProfileBioFieldTitle => 'Biografia';

  @override
  String get editProfileBioFieldLabel => 'Conte-nos sobre você';

  @override
  String get editProfileScreenTitle => 'Editar perfil';

  @override
  String get editProfileSettingTitle => 'Configurações da conta';

  @override
  String get editProfileSettingSubtitle => 'Gerencie sua conta';

  @override
  String get editProfileScreenEditShopTitle => 'Editar Loja';

  @override
  String get editProfileScreenEditShopSubtitle => 'Altere as informações da sua loja';

  @override
  String get languageScreenSubtitle => 'Escolha seu idioma preferido para a interface do app. Isso não afetará as configurações do seu dispositivo.';

  @override
  String get languageScreeUseDeviceLang => 'Usar Idioma do Dispositivo.';

  @override
  String get languageScreeUseDeviceLangNote => 'Isso será redefinido para coincidir com o idioma do sistema do seu dispositivo.';

  @override
  String get settingsScreenTitle => 'Configurações';

  @override
  String get accountSectionTitle => 'Conta';

  @override
  String get accountSectionSubtitle => '';

  @override
  String get profileItemTitle => 'Perfil';

  @override
  String get profileItemSubtitle => 'Gerencie seus dados pessoais';

  @override
  String get locationItemTitle => 'Alterar Localização';

  @override
  String get locationItemSubtitle => 'Altere sua cidade atual';

  @override
  String get saveItemTitle => 'Conteúdos Salvos';

  @override
  String get saveItemSubtitle => 'Conteúdos que você salvou';

  @override
  String get notificationsItemTitle => 'Notificações';

  @override
  String get notificationsItemSubtitle => 'Gerencie notificações push e email';

  @override
  String get blockedItemTitle => 'Contas Bloqueadas';

  @override
  String get blockedItemSubtitle => 'Contas que você bloqueou';

  @override
  String get mutedItemTitle => 'Contas Silenciadas';

  @override
  String get mutedItemSubtitle => 'Contas anônimas do Opinions que você silenciou';

  @override
  String get qrCodeItemTitle => 'Compartilhar Código QR';

  @override
  String get qrCodeItemSubtitle => 'Compartilhe seu código QR da conta';

  @override
  String get shareProfileItemTitle => 'Compartilhar Perfil';

  @override
  String get shareProfileItemSubtitle => 'Compartilhe seu perfil com amigos';

  @override
  String get appSettingsSectionTitle => 'Configurações do App';

  @override
  String get appSettingsSectionSubtitle => 'Personalize sua experiência';

  @override
  String get themeItemTitle => 'Tema';

  @override
  String get themeItemSubtitle => 'Claro, Escuro ou Sistema';

  @override
  String get languageItemTitle => 'Idioma';

  @override
  String get languageItemSubtitle => 'Altere o idioma do app';

  @override
  String get biometricItemTitle => 'Login Biométrico';

  @override
  String get biometricItemSubtitle => 'Use Face ID ou Touch ID';

  @override
  String get supportSectionTitle => 'Suporte';

  @override
  String get supportSectionSubtitle => '';

  @override
  String get guideItemTitle => 'Guia do Usuário';

  @override
  String get guideItemSubtitle => 'Documentação e tutoriais';

  @override
  String get helpItemTitle => 'Contatar Suporte';

  @override
  String get helpItemSubtitle => 'Obtenha ajuda com o app';

  @override
  String get feedbackItemTitle => 'Enviar Feedback';

  @override
  String get feedbackItemSubtitle => 'Compartilhe seus pensamentos';

  @override
  String get rateItemTitle => 'Avaliar o App';

  @override
  String get rateItemSubtitle => 'Deixe uma avaliação';

  @override
  String appInfoItemTitle(String appName) {
    return 'Sobre o $appName';
  }

  @override
  String get appInfoItemSubtitle => 'Informações técnicas';

  @override
  String get legalSectionTitle => 'Legal';

  @override
  String get legalSectionSubtitle => '';

  @override
  String get termsItemTitle => 'Termos, Privacidade e Políticas';

  @override
  String get termsItemSubtitle => 'Leia nossos termos';

  @override
  String get licensesItemTitle => 'Licenças de Código Aberto';

  @override
  String get licensesItemSubtitle => 'Bibliotecas e licenças de terceiros';

  @override
  String get accountActionsSectionTitle => 'Ações da Conta';

  @override
  String get accountActionsSectionSubtitle => '';

  @override
  String get deactivateItemTitle => 'Desativar';

  @override
  String get deactivateItemSubtitle => 'Desative sua conta';

  @override
  String get deleteItemTitle => 'Excluir Conta';

  @override
  String get deleteItemSubtitle => 'Remova permanentemente sua conta';

  @override
  String get logoutItemTitle => 'Sair';

  @override
  String get logoutItemSubtitle => 'Saia da sua conta';

  @override
  String get loadingDefaultMessage => 'Carregando...';

  @override
  String get emptyStateNoDataTitle => 'Nada aqui ainda';

  @override
  String get emptyStateNoDataSubtitle => 'Quando houver algo para mostrar, aparecerá aqui.';

  @override
  String get emptyStateNoResultsTitle => 'Nenhuma correspondência';

  @override
  String get emptyStateNoResultsSubtitle => 'Tente outra palavra ou outro filtro.';

  @override
  String get emptyStateNoInternetTitle => 'Você está offline';

  @override
  String get emptyStateNoInternetSubtitle => 'Verifique sua conexão e tente novamente.';

  @override
  String get emptyStateNoMessagesTitle => 'Ainda não há mensagens';

  @override
  String get emptyStateNoMessagesSubtitle => 'Diga olá para começar a conversa de vocês.';

  @override
  String get emptyStateRefresh => 'Atualizar';

  @override
  String get emptyStateClearFilters => 'Limpar filtros';

  @override
  String get emptyStateRetry => 'Tentar novamente';

  @override
  String get emptyStateStartChat => 'Dizer olá';

  @override
  String get errorNetworkTitle => 'Erro de conexão';

  @override
  String get errorNetworkSubtitle => 'Não foi possível conectar ao servidor. Verifique sua conexão com a internet.';

  @override
  String get errorServerTitle => 'Erro do servidor';

  @override
  String get errorServerSubtitle => 'Algo deu errado do nosso lado. Por favor, tente novamente mais tarde.';

  @override
  String get errorClientTitle => 'Erro na solicitação';

  @override
  String get errorClientSubtitle => 'Houve um problema com sua solicitação. Por favor, verifique e tente novamente.';

  @override
  String get errorParsingTitle => 'Erro de dados';

  @override
  String errorParsingSubtitle(String dataType) {
    return 'Não foi possível processar o(a) $dataType. Isso pode ser um problema temporário.';
  }

  @override
  String get errorPermissionTitle => 'Acesso negado';

  @override
  String errorPermissionSubtitle(String dataType) {
    return 'Você não tem permissão para acessar este(a) $dataType.';
  }

  @override
  String get errorGenericTitle => 'Algo deu errado';

  @override
  String errorGenericSubtitle(String dataType) {
    return 'Ocorreu um erro inesperado ao carregar $dataType. Por favor, tente novamente.';
  }

  @override
  String get errorRetry => 'Tentar novamente';

  @override
  String get errorCheckSettings => 'Verificar configurações';

  @override
  String get errorReport => 'Reportar problema';

  @override
  String get errorGoBack => 'Voltar';

  @override
  String get errorRefresh => 'Atualizar';

  @override
  String get errorRequestAccess => 'Solicitar acesso';

  @override
  String get errorContactSupport => 'Contatar suporte';

  @override
  String get eulaTitle => 'Contrato de Licença de Usuário Final';

  @override
  String eulaContent(String appName, String supportEmail) {
    return 'Este Contrato de Licença de Usuário Final (\"EULA\") é um acordo legal entre você e a Bars Opus, Ltd. para $appName.\n\nAo instalar, acessar ou usar $appName, você concorda em ficar vinculado aos termos deste EULA. $appName é licenciado, não vendido, para seu uso apenas sob os termos desta licença. A Bars Opus, Ltd. reserva-se todos os direitos não expressamente concedidos a você neste EULA.\n\nVocê não pode modificar, fazer engenharia reversa, descompilar ou desmontar $appName. Esta licença é válida até ser rescindida por você ou pela Bars Opus, Ltd. Seus direitos sob esta licença terminarão automaticamente sem aviso se você não cumprir qualquer termo.\n\nTodos os direitos de propriedade intelectual sobre $appName pertencem à Bars Opus, Ltd. Este EULA é regido pelas leis da Inglaterra e do País de Gales.\n\nPara perguntas sobre este EULA, entre em contato: $supportEmail.';
  }

  @override
  String get eulaFooter => 'Ao concordar, você reconhece que leu e entendeu este Contrato de Licença de Usuário Final.';

  @override
  String get privacyPolicyTitle => 'Política de Privacidade';

  @override
  String privacyPolicyContent(String appName) {
    return 'Esta Política de Privacidade explica como a Bars Opus, Ltd. (\"nós\", \"nosso\") coleta, usa e protege suas informações quando você usa $appName.\n\nColetamos informações que você fornece diretamente, como quando cria uma conta, completa seu perfil ou entra em contato com o suporte. Coletamos automaticamente certas informações sobre seu dispositivo e como você usa $appName. Usamos cookies e tecnologias de rastreamento semelhantes para rastrear a atividade e armazenar determinadas informações.\n\nUsamos as informações que coletamos para fornecer, manter e melhorar $appName. Podemos compartilhar suas informações com provedores de serviços terceirizados que realizam serviços em nosso nome. Podemos divulgar suas informações se exigido por lei ou para proteger nossos direitos e segurança.\n\nVocê tem o direito de acessar, corrigir ou excluir suas informações pessoais. Implementamos medidas técnicas e organizacionais adequadas para proteger suas informações. Podemos atualizar esta Política de Privacidade periodicamente. Iremos notificá-lo sobre quaisquer alterações.';
  }

  @override
  String privacyPolicyFooter(String appName, DateTime currentDate) {
    final intl.DateFormat currentDateDateFormat = intl.DateFormat.yMMMMd(localeName);
    final String currentDateString = currentDateDateFormat.format(currentDate);

    return 'Política de Privacidade do $appName - Última atualização: $currentDateString';
  }

  @override
  String get termsTitle => 'Termos de Serviço';

  @override
  String termsContent(String appName, String supportEmail) {
    return 'Estes Termos de Serviço (\"Termos\") regem seu acesso e uso de $appName. Ao acessar ou usar $appName, você concorda em ficar vinculado a estes Termos.\n\nVocê deve ter pelo menos 13 anos para usar $appName. Você é responsável por proteger suas credenciais de conta e por todas as atividades sob sua conta. Você não pode usar $appName para qualquer finalidade ilegal ou não autorizada.\n\nReservamo-nos o direito de modificar, suspender ou descontinuar $appName a qualquer momento. Todo o conteúdo incluído em $appName é propriedade da Bars Opus, Ltd. ou de seus licenciadores.\n\nPodemos encerrar ou suspender seu acesso a $appName imediatamente se você violar estes Termos. Estes Termos serão regidos e interpretados de acordo com as leis da Inglaterra e do País de Gales.\n\nPara quaisquer perguntas sobre estes Termos, entre em contato conosco em $supportEmail.';
  }

  @override
  String get dataSharingTitle => 'Acordo de Compartilhamento de Dados';

  @override
  String dataSharingContent(String appName) {
    return 'Este Acordo de Compartilhamento de Dados descreve como suas informações podem ser compartilhadas quando você usa os recursos sociais do $appName.\n\nQuando você se conecta com amigos no $appName, certos dados de atividade podem ser visíveis para eles. Os dados de atividade compartilhados podem incluir duração do treino, calorias queimadas, minutos de exercício e emblemas de conquistas. Suas informações de perfil (nome de exibição e foto do perfil) são visíveis para amigos com quem você se conecta.\n\nSeu endereço de e-mail e informações de contato permanecem privados e nunca são compartilhados com outros usuários. Você controla quais dados são compartilhados através das suas configurações de privacidade do $appName. Você pode revogar as permissões de compartilhamento a qualquer momento nas configurações do aplicativo.\n\nOs dados compartilhados com amigos são criptografados durante a transmissão e armazenamento. Mantemos os dados compartilhados apenas pelo tempo necessário para fornecer a funcionalidade de compartilhamento. As integrações de terceiros podem ter suas próprias práticas de compartilhamento de dados, que recomendamos revisar.';
  }

  @override
  String dataSharingFooter(String appName) {
    return 'O compartilhamento de dados no $appName ajuda a criar uma comunidade de apoio, respeitando suas escolhas de privacidade.';
  }

  @override
  String get dashboardTitle => 'Painel de Controle';

  @override
  String get dashboardSubtitle => 'Gerencie as atividades da sua loja de forma eficiente';

  @override
  String get dashboardSectionTitle => 'Painel de Controle';

  @override
  String get dashboardSectionSubtitle => 'Visão geral do desempenho e métricas principais da sua loja';

  @override
  String get dashboardPayoutTitle => 'Solicitar Pagamento';

  @override
  String get dashboardPayoutContent => 'Proprietários de lojas podem solicitar pagamentos semanais. Navegue até a seção Ganhos, revise seu saldo e envie uma solicitação de pagamento. Os fundos geralmente são processados em 3-5 dias úteis.';

  @override
  String get dashboardAnalyticsTitle => 'Painel Analítico';

  @override
  String get dashboardAnalyticsContent => 'Acompanhe o desempenho da sua loja com análises em tempo real. Monitore tendências de vendas, engajamento do cliente e níveis de estoque por meio de gráficos interativos e relatórios.';

  @override
  String get dashboardScreenshotTitle => 'Visão Geral do Painel';

  @override
  String get dashboardScreenshotContent => 'O painel principal fornece uma visão abrangente das principais métricas da sua loja, atividades recentes e acesso rápido a recursos essenciais.';

  @override
  String get categoryFeatures => 'Recursos';

  @override
  String get categoryDashboard => 'Painel de Controle';

  @override
  String get faqDashboard1Question => 'Quando posso solicitar um pagamento?';

  @override
  String get faqDashboard1Answer => 'Você pode solicitar seu pagamento uma vez por semana, todo sábado. O corte semanal é sexta-feira às 23:59. Os pagamentos são processados em 3-5 dias úteis.';

  @override
  String get faqDashboard2Question => 'Onde posso solicitar meu pagamento?';

  @override
  String get faqDashboard2Answer => 'Navegue até seu painel de controle e clique na seção \'Ganhos\'. De lá, você verá seu saldo atual e um botão \'Solicitar Pagamento\'. Siga as instruções para completar sua solicitação.';

  @override
  String get profileScreenCantChatWithYourself => 'Você não pode conversar consigo mesmo';

  @override
  String get profileScreenStartingConversation => 'Iniciando conversa...';

  @override
  String get profileScreenNoActiveSession => 'Nenhuma sessão ativa — faça login novamente.';

  @override
  String get profileScreenSignInToChatMessage => 'Você deve fazer login para enviar uma mensagem';

  @override
  String get profileScreenFollowFeatureComingSoon => 'Recurso de seguimento em breve';

  @override
  String get profileScreenEnterBioPlaceholder => 'Digite uma biografia para que as pessoas o conheçam';

  @override
  String get profileScreenNoBioYet => 'Nenhuma biografia ainda';

  @override
  String get profileScreenErrorLoadingProfileBody => 'Não foi possível carregar o perfil. Verifique sua conexão de internet e tente novamente.';

  @override
  String get profileScreenLoadingNotifications => 'Carregando...';

  @override
  String get profileHeaderBookingsStatLabel => 'Reservas';

  @override
  String get profileHeaderOrdersStatLabel => 'Pedidos';

  @override
  String get profileHeaderEditProfileButton => 'Editar perfil';

  @override
  String get profileHeaderMessageButton => 'Mensagem';

  @override
  String get editableProfileAvatarTakePhoto => 'Tire uma foto';

  @override
  String get editableProfileAvatarChooseGallery => 'Escolher da galeria';

  @override
  String get editProfileScreenAccountTypeLabel => 'Tipo de conta';

  @override
  String get editProfileScreenAccountTypeSubtitle => 'Selecione como deseja usar este aplicativo. Isso determina quais recursos estão disponíveis para você.';

  @override
  String get editProfileScreenUpdatingAccountType => 'Atualizando tipo de conta...';

  @override
  String get editProfileScreenPleaseLogIn => 'Faça login por favor';

  @override
  String get editProfileScreenNameLabel => 'Nome';

  @override
  String get editProfileScreenNameHint => 'Insira seu nome';

  @override
  String get editProfileScreenUsernameLabel => 'Nome de usuário';

  @override
  String get editProfileScreenUsernameHint => 'Insira o nome de usuário';

  @override
  String get editProfileScreenBioLabel => 'Biografia';

  @override
  String get editProfileScreenBioHint => 'Conte-nos sobre você';

  @override
  String get editProfileScreenEditWorkProfileTitle => 'Editar perfil de trabalho';

  @override
  String get profileTabsAppointments => 'Compromissos';

  @override
  String get profileTabsBuys => 'Compras';

  @override
  String get profileTabsSaves => 'Salvos';

  @override
  String get searchScreenSearchHint => 'Pesquise lojas, profissionais, produtos...';

  @override
  String get searchScreenNoResultsFound => 'Nenhum resultado encontrado';

  @override
  String searchScreenNoResultsCategory(String category) {
    return 'Nenhum $category encontrado';
  }

  @override
  String searchScreenSearchedFor(String query) {
    return 'Pesquisado: \"$query\"';
  }

  @override
  String get searchScreenSomethingWentWrong => 'Algo deu errado';

  @override
  String get searchAppBarSearchHint => 'Pesquisar...';

  @override
  String get searchSuggestionsHint => 'Pesquise lojas, profissionais de serviços domiciliares ou produtos para cabelo para comprar';

  @override
  String get searchSuggestionsRecentSearches => 'Pesquisas recentes';

  @override
  String get searchSuggestionsClearAll => 'Limpar tudo';

  @override
  String get searchEmptyStateNoResults => 'Nenhum resultado encontrado';

  @override
  String searchEmptyStateCouldNotFind(String query) {
    return 'Não encontramos nada para \"$query\"';
  }

  @override
  String get searchEmptyStateTryThese => 'Tente estes:';

  @override
  String get searchResultsShopsHeader => 'Lojas';

  @override
  String get searchResultsSeeAll => 'Ver tudo';

  @override
  String searchResultsTitle(String category) {
    return 'Resultados de $category';
  }

  @override
  String searchResultsSearchingFor(String query) {
    return 'Pesquisando \"$query\"';
  }

  @override
  String get searchResultsTryDifferent => 'Tente palavras-chave diferentes ou remova filtros';

  @override
  String get searchResultsSomethingWentWrong => 'Algo deu errado';

  @override
  String nearYouShopsTitle(int km) {
    return 'Perto de você\ndenro de ${km}km';
  }

  @override
  String nearYouShopsBody(int km) {
    return 'Lojas localizadas dentro de $km km da sua localização atual, mostradas da mais próxima para a mais distante. Simplesmente defina sua localização uma vez, e mostraremos o que está por perto—seja em casa, no trabalho ou explorando um novo bairro. Útil para reservas de última hora ou quando você prefere caminhar.';
  }

  @override
  String get nearYouShopsEmptyNoFilter => 'Nenhuma loja encontrada perto de você';

  @override
  String nearYouShopsEmptyWithFilter(String luxury) {
    return 'Nenhuma loja $luxury encontrada perto de você';
  }

  @override
  String nearYouShopsEmptySubtitle(String location) {
    return 'As lojas em $location seriam exibidas aqui assim que ficassem disponíveis';
  }

  @override
  String get premiumShopsScreenTitle => 'Lojas Premium';

  @override
  String get premiumShopsEmpty => 'Nenhuma loja premium encontrada';

  @override
  String get premiumShopsHorizontalTitle => 'Lojas premium\npara looks premium';

  @override
  String get premiumShopsHorizontalBody => 'Salões e spas de luxo cuidadosamente selecionados que oferecem experiências luxuosas. Estas lojas são classificadas como Luxo ou Ultra-Luxo com base em seus serviços, preços e avaliações de clientes. Perfeito quando você quer aquele toque extra de elegância.';

  @override
  String get premiumShopsHorizontalEmptyNoFilter => 'Nenhuma loja premium disponível';

  @override
  String premiumShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Nenhuma loja premium $luxury disponível';
  }

  @override
  String get premiumShopsHorizontalEmptySubtitle => 'As lojas seriam exibidas aqui uma vez que ficassem disponíveis';

  @override
  String get topRatedShopsHorizontalTitle => 'Mais bem avaliado';

  @override
  String topRatedShopsHorizontalTitleWithLocation(String location) {
    return 'Mais bem avaliado \nem $location';
  }

  @override
  String get topRatedShopsHorizontalBody => 'Lojas com as avaliações mais altas de clientes (4,5+ estrelas) e muitas resenhas. Estes são os favoritos da nossa comunidade—constantemente elogiados por qualidade, serviço e profissionalismo. Um ótimo lugar para começar se você quer opções confiáveis e aprovadas pela multidão.';

  @override
  String get topRatedShopsHorizontalEmptyNoFilter => 'Nenhuma loja bem avaliada disponível';

  @override
  String topRatedShopsHorizontalEmptyWithFilter(String luxury) {
    return 'Nenhuma loja premium $luxury disponível';
  }

  @override
  String get topRatedShopsHorizontalEmptySubtitle => 'As lojas seriam exibidas aqui uma vez que ficassem disponíveis';

  @override
  String get topRatedShopsScreenTitle => 'Lojas Mais Bem Avaliadas';

  @override
  String get topRatedShopsEmpty => 'Nenhuma loja bem avaliada encontrada';

  @override
  String get nearYouFreelancersScreenTitle => 'Freelancers perto de você';

  @override
  String get nearYouFreelancersEmpty => 'Nenhum freelancer encontrado perto';

  @override
  String get nearYouFreelancersEmptySubtitle => 'Tente expandir sua área de pesquisa ou mude de localização';

  @override
  String get topRatedFreelancersScreenTitle => 'Freelancers mais bem avaliados';

  @override
  String get topRatedFreelancersEmpty => 'Nenhum freelancer bem avaliado encontrado';

  @override
  String get topRatedFreelancersEmptySubtitle => 'Tente ajustar sua área de pesquisa';

  @override
  String topRatedFreelancersHorizontalTitle(String location) {
    return 'Mais bem avaliados \nem $location';
  }

  @override
  String get topRatedFreelancersHorizontalBody => 'Profissionais altamente qualificados cuidadosamente selecionados que oferecem experiências luxuosas. Estes freelancers são classificados como mais bem avaliados com base na qualidade de seu trabalho, preços e avaliações de clientes. Perfeito para aquele toque extra de excelência.';

  @override
  String nearYouFreelancersHorizontalTitle(String location) {
    return 'Freelancers Perto de Você em $location';
  }

  @override
  String get nearYouFreelancersHorizontalBody => 'Profissionais qualificados localizados perto de você. Estes freelancers estão disponíveis para reservas rápidas e oferecem serviço local conveniente. Perfeito quando você busca confiabilidade e proximidade.';

  @override
  String get nearYouFreelancersHorizontalEmpty => 'Nenhum freelancer bem avaliado disponível';

  @override
  String get nearYouFreelancersHorizontalEmptySubtitle => 'Os freelancers seriam exibidos aqui uma vez que ficassem disponíveis';

  @override
  String get shopNoLocationSetTitle => 'Defina sua localização para descobrir';

  @override
  String get shopNoLocationSetContent => 'Defina sua localização para descobrir lojas premium e bem avaliadas perto de você.';

  @override
  String get providerTypeShops => 'Lojas';

  @override
  String get providerTypeFreelancers => 'Freelancers';

  @override
  String get providerTypeBuy => 'Comprar';

  @override
  String get luxuryLevelChipsAll => 'Todos';

  @override
  String get searchRadiusSliderTitle => 'Raio de exploração';

  @override
  String searchRadiusSliderSubtitle(int km) {
    return 'Mostrando resultados dentro de ${km}km da sua localização';
  }

  @override
  String validationPasswordMaxLength(int max) {
    return 'A senha não deve exceder $max caracteres';
  }

  @override
  String get validationPasswordRepeatingChars => 'A senha contém muitos caracteres repetidos';

  @override
  String get validationPasswordSequential => 'A senha contém caracteres sequenciais';

  @override
  String validationPhoneDigits(int digits) {
    return 'O número de telefone deve ter $digits dígitos';
  }

  @override
  String get validationPhoneUK => 'Número de telefone britânico inválido';

  @override
  String validationUrlScheme(String schemes) {
    return 'A URL deve começar com $schemes';
  }

  @override
  String get validationUrlDomain => 'Nome de domínio inválido';

  @override
  String get validationUrlPublicAddress => 'A URL deve apontar para um endereço público';

  @override
  String validationNameMaxLength(String field, int max) {
    return '$field não deve exceder $max caracteres';
  }

  @override
  String validationNameConsecutiveChars(String field) {
    return '$field não pode conter hífens ou espaços consecutivos';
  }

  @override
  String get validationCreditCardFormat => 'Por favor, digite um número de cartão de crédito válido';

  @override
  String get validationCreditCardInvalid => 'Número de cartão de crédito inválido';

  @override
  String get validationDatePastNotAllowed => 'A data não pode ser no passado';

  @override
  String get validationPostalCodeZip => 'Por favor, digite um CEP válido (ex. 12345 ou 12345-6789)';

  @override
  String get validationPostalCodeCanadian => 'Por favor, digite um código postal canadense válido (ex. A1A 1A1)';

  @override
  String get validationPostalCodeGeneric => 'Por favor, digite um código postal válido';

  @override
  String get validationSSNFormat => 'Por favor, digite um SSN válido (ex. 123-45-6789)';

  @override
  String get validationSSNInvalid => 'SSN inválido';

  @override
  String get validationEmailTooLong => 'O endereço de e-mail é muito longo (máx. 254 caracteres)';

  @override
  String get validationEmailLocalPartTooLong => 'A parte local do endereço de e-mail é muito longa';

  @override
  String get categoriesAll => 'Todos';

  @override
  String get categoriesSalon => 'Salões';

  @override
  String get categoriesBarbershop => 'Barbearias';

  @override
  String get categoriesSpa => 'Spas';

  @override
  String get categoriesNailSalon => 'Salões de Unhas';

  @override
  String get categoriesLashStudio => 'Estúdios de Cílios';

  @override
  String get categoriesWaxing => 'Depilação';

  @override
  String get categoriesMassage => 'Massagem';

  @override
  String get categoriesMakeup => 'Maquiagem';

  @override
  String get categoriesSkincare => 'Cuidados com a Pele';

  @override
  String get luxuryLevelModerate => 'Moderado';

  @override
  String get luxuryLevelLuxury => 'Luxo';

  @override
  String get luxuryLevelUltraLuxury => 'Ultra Luxo';

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

  @override
  String get opinions_filterContactInfo => 'Phone numbers, emails, links and usernames can\'t go in Opinions. They can identify you or someone else. Take it out and post again.';

  @override
  String get opinions_filterSlur => 'This includes a word that attacks people for who they are. Opinions doesn\'t allow it.';

  @override
  String get opinions_filterExplicit => 'Opinions doesn\'t allow sexual content. You can describe what happened without explicit words.';

  @override
  String get opinions_filterQuoted => 'The comment you\'re replying to can\'t be quoted in Opinions. Your own words are fine. Close the reply and post again.';

  @override
  String get opinions_filterPollOption => 'It\'s in one of your poll options.';

  @override
  String get support_needSupportNow => 'Need support now?';

  @override
  String get opinions_reportAtRisk => 'Someone may be at risk';

  @override
  String get opinions_atRiskThanks => 'Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.';

  @override
  String get opinions_atRiskSeeNumbers => 'See emergency numbers';

  @override
  String get opinions_atRiskClose => 'Close';

  @override
  String get opinions_reportFailed => 'Couldn\'t send your report. Please try again.';

  @override
  String get opinions_reportSent => 'Thank you. Your report has been sent.';

  @override
  String get opinions_reportSending => 'Sending your report';

  @override
  String get journal_supportCardBody => 'If things feel heavy right now, you don\'t have to carry it alone. Support is here if you want it.';

  @override
  String get journal_supportSeeSupport => 'See support';

  @override
  String get journal_supportNotNow => 'Not now';

  @override
  String get journal_supportPatternsAway => 'Patterns will show here again later';

  @override
  String get journal_supportPatternsAwayBody => 'Your entries are saved and stay private to you.';

  @override
  String get dating_gentleWaitTitle => 'Before you begin';

  @override
  String dating_gentleWaitBody(String endDate, String openDate) {
    return 'Your relationship on Attune ended on $endDate. Dating opens for you on $openDate, when your shared space closes. If you both close it sooner, Dating opens then.';
  }

  @override
  String get dating_gentleWaitNotJudgement => 'This pause is because your relationship ended here. It isn\'t a judgement about you.';

  @override
  String get dating_gentleWaitQuestionsTitle => 'Three questions, just for you';

  @override
  String get dating_gentleWaitQuestionsHint => 'Only you can see these, and nothing is scored.';

  @override
  String get dating_gentleWaitQuestion1 => 'What do you want to carry into your next relationship?';

  @override
  String get dating_gentleWaitQuestion2 => 'What are you hoping for now?';

  @override
  String get dating_gentleWaitQuestion3 => 'How will you know if you need more time?';

  @override
  String dating_gentleWaitAnswerCount(int count, int max) {
    return '$count of $max characters';
  }

  @override
  String get dating_gentleWaitSave => 'Save my answers';

  @override
  String get dating_gentleWaitSaved => 'Your answers are saved.';

  @override
  String get dating_gentleWaitHealing => 'Healing is here if you want it. It\'s there to help, and it\'s never required.';

  @override
  String get dating_gentleWaitSetUp => 'Set up Dating now';

  @override
  String get dating_offline => 'You\'re offline. Dating needs a connection.';

  @override
  String get dating_connectToSave => 'Connect to save this answer.';

  @override
  String get dating_errorGeneric => 'Something went wrong. Try again.';

  @override
  String get dating_retry => 'Retry';

  @override
  String get dating_gentleWaitClear => 'Clear my answers';

  @override
  String get dating_gentleWaitCleared => 'Your answers are cleared.';

  @override
  String get dating_gentleWaitBusy => 'This is taking a little longer than usual. Your answers are still here, so try again in a moment.';

  @override
  String get dating_busy => 'This is taking a little longer than usual. Try again in a moment.';

  @override
  String get dating_gentleWaitClearBusy => 'This is taking a little longer than usual. Try clearing again in a moment.';

  @override
  String dating_gentleWaitBodyNoShortcut(String endDate, String openDate) {
    return 'Your relationship on Attune ended on $endDate. Dating opens for you on $openDate.';
  }

  @override
  String get dating_unlockButton => 'Enter my PIN';

  @override
  String get dating_sectionReverify => 'Confirm it\'s you on this phone to see Dating.';

  @override
  String get dating_gentleWaitNotEligible => 'Dating isn\'t available on this account right now, so your answers weren\'t saved.';

  @override
  String get dating_countryUk => 'the United Kingdom';

  @override
  String dating_countryWithRegions(String country, String regions) {
    return '$country ($regions)';
  }

  @override
  String dating_sectionNotOpen(String country) {
    return 'Dating isn\'t open in $country yet.';
  }

  @override
  String dating_sectionRegionOpenOnly(String regions) {
    return 'Dating is open in $regions for now.';
  }

  @override
  String get dating_tellMe => 'Tell me when it\'s here';

  @override
  String dating_tellMeRegion(String region) {
    return 'Tell me when it\'s open in $region';
  }

  @override
  String get dating_tellMeDone => 'We\'ll let you know. You can turn this off in Settings.';

  @override
  String get dating_tellMeOff => 'Turn this off';

  @override
  String dating_notOpenTitle(String country) {
    return 'Dating isn\'t open in $country yet';
  }

  @override
  String dating_notOpenBody(String countries) {
    return 'Attune opens Dating one country at a time, so we can keep it safe and well looked after. It\'s open in $countries now.';
  }

  @override
  String dating_notOpenRegionTitle(String regions) {
    return 'Dating is open in $regions for now';
  }

  @override
  String get dating_notOpenRegionBody => 'We\'re opening other regions as soon as we can look after them well.';

  @override
  String get dating_justForMe => 'Use Attune just for me';

  @override
  String get dating_sectionNotStarted => 'Meet a few people a day. Only when it\'s mutual.';

  @override
  String get dating_sectionFinish => 'Finish setting up Dating';

  @override
  String dating_sectionFirstDrop(String date, String time) {
    return 'Your first introductions arrive $date at $time.';
  }

  @override
  String get dating_sectionActive => 'Dating is on. Your introductions will show here.';

  @override
  String get dating_sectionPaused => 'Dating is paused. Nobody new sees you.';

  @override
  String get dating_resume => 'Resume';

  @override
  String get dating_sectionPausedRelationship => 'Dating is paused while you have a shared space on Attune.';

  @override
  String dating_sectionSameGenderNote(String country) {
    return 'Introductions between people of the same gender aren\'t available in $country now. We\'ve removed that choice from your profile.';
  }

  @override
  String get dating_why => 'Why?';

  @override
  String dating_whyBody(String country) {
    return 'In $country, relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know. Until we can protect people properly here, Attune only introduces men and women to each other. Nothing you choose here is stored unless you continue. We\'ll look at this again after legal advice and talking with local groups.';
  }

  @override
  String get dating_close => 'Close';

  @override
  String get dating_chooseAgain => 'Choose again';

  @override
  String get dating_sectionAway => 'Dating is hidden while you\'re away.';

  @override
  String get dating_sectionRestricted => 'Your Dating account is restricted. The rest of Attune works as usual.';

  @override
  String get dating_sectionHold => 'Your Dating profile is paused while we look into something. This isn\'t a decision yet.';

  @override
  String get dating_sectionAgeReview => 'We need to confirm your age before you can use Dating.';

  @override
  String get dating_sectionUnavailable => 'Dating isn\'t available on this account right now.';

  @override
  String get dating_sectionLockedLabel => 'Dating, locked';

  @override
  String get dating_settingsTitle => 'Dating settings';

  @override
  String get dating_settingsNotice => 'Tell me when Dating opens';

  @override
  String get dating_settingsClearReflection => 'Clear my answers to the three questions';

  @override
  String get dating_errorPathNotDating => 'Choose Dating in How you use Attune to carry on.';

  @override
  String get dating_openHowYouUse => 'How you use Attune';

  @override
  String get dating_errorResumeGates => 'Dating can\'t resume on this account right now.';

  @override
  String get dating_errorConsent => 'Agree to Dating\'s terms again to carry on.';

  @override
  String get dating_errorIncomplete => 'Finish setting up Dating first.';

  @override
  String get dating_errorRateLimited => 'You\'ve done this a lot today. Try again tomorrow.';

  @override
  String get dating_region_gh_af => 'Ahafo';

  @override
  String get dating_region_gh_ah => 'Ashanti';

  @override
  String get dating_region_gh_bo => 'Bono';

  @override
  String get dating_region_gh_be => 'Bono East';

  @override
  String get dating_region_gh_cp => 'Central';

  @override
  String get dating_region_gh_ep => 'Eastern';

  @override
  String get dating_region_gh_aa => 'Greater Accra';

  @override
  String get dating_region_gh_ne => 'North East';

  @override
  String get dating_region_gh_np => 'Northern';

  @override
  String get dating_region_gh_ot => 'Oti';

  @override
  String get dating_region_gh_sv => 'Savannah';

  @override
  String get dating_region_gh_ue => 'Upper East';

  @override
  String get dating_region_gh_uw => 'Upper West';

  @override
  String get dating_region_gh_tv => 'Volta';

  @override
  String get dating_region_gh_wp => 'Western';

  @override
  String get dating_region_gh_wn => 'Western North';

  @override
  String get dating_side_gh_accra => 'Accra';

  @override
  String get dating_side_gh_tema => 'Tema and Ashaiman';

  @override
  String get dating_side_gh_kumasi => 'Kumasi';

  @override
  String get dating_side_gh_outside_kumasi => 'Outside Kumasi';

  @override
  String get dating_region_gb_tlc => 'North East';

  @override
  String get dating_region_gb_tld => 'North West';

  @override
  String get dating_region_gb_tle => 'Yorkshire and the Humber';

  @override
  String get dating_region_gb_tlf => 'East Midlands';

  @override
  String get dating_region_gb_tlg => 'West Midlands';

  @override
  String get dating_region_gb_tlh => 'East of England';

  @override
  String get dating_region_gb_tli => 'London';

  @override
  String get dating_region_gb_tlj => 'South East';

  @override
  String get dating_region_gb_tlk => 'South West';

  @override
  String get dating_region_gb_tll => 'Wales';

  @override
  String get dating_region_gb_tlm => 'Scotland';

  @override
  String get dating_region_gb_tln => 'Northern Ireland';

  @override
  String get dating_noticeNotEligible => 'We can\'t set this up on this account.';

  @override
  String get dating_faith_christian => 'Christian';

  @override
  String get dating_faith_muslim => 'Muslim';

  @override
  String get dating_faith_traditional => 'Traditional';

  @override
  String get dating_faith_hindu => 'Hindu';

  @override
  String get dating_faith_sikh => 'Sikh';

  @override
  String get dating_faith_jewish => 'Jewish';

  @override
  String get dating_faith_buddhist => 'Buddhist';

  @override
  String get dating_faith_other => 'Other';

  @override
  String get dating_faith_none => 'None';

  @override
  String get dating_faith_prefer_not_to_say => 'Prefer not to say';

  @override
  String get dating_denomination_catholic => 'Catholic';

  @override
  String get dating_denomination_anglican => 'Anglican';

  @override
  String get dating_denomination_methodist => 'Methodist';

  @override
  String get dating_denomination_presbyterian => 'Presbyterian';

  @override
  String get dating_denomination_pentecostal_charismatic => 'Pentecostal or Charismatic';

  @override
  String get dating_denomination_seventh_day_adventist => 'Seventh-day Adventist';

  @override
  String get dating_denomination_other_christian => 'Other Christian';

  @override
  String get dating_denomination_church_of_england_anglican => 'Church of England or Anglican';

  @override
  String get dating_denomination_orthodox => 'Orthodox';

  @override
  String dating_stepOf(int n, int total) {
    return 'Step $n of $total';
  }

  @override
  String get dating_skip => 'Skip';

  @override
  String get dating_continue => 'Continue';

  @override
  String get dating_notAvailableHere => 'This choice isn\'t available here.';

  @override
  String get dating_contactFilter => 'Contact details can\'t go on your profile. You can swap them in a chat when you\'re both ready.';

  @override
  String get dating_kindnessFilter => 'Please rephrase this so it\'s kind to everyone.';

  @override
  String get dating_countryChangeLimited => 'You can change your Dating country once every 30 days.';

  @override
  String get dating_howTitle => 'How Dating works';

  @override
  String get dating_how1 => 'Up to 3 introductions a day, at a time you choose.';

  @override
  String get dating_how2 => 'Saying \'Interested\' is private. You only match when you\'re both interested.';

  @override
  String get dating_how3 => 'Dating chats are separate from the rest of Attune. Phone numbers stay hidden until you both choose to swap.';

  @override
  String get dating_how4 => 'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.';

  @override
  String get dating_how5 => 'You\'ll add at least 2 photos and answer 2 short questions.';

  @override
  String dating_how6(String date) {
    return 'Your first introductions can arrive from $date.';
  }

  @override
  String dating_how7(String countries) {
    return 'Dating is open in $countries.';
  }

  @override
  String get dating_how8 => 'Setting up uses about 15 MB of data, mostly for the video check.';

  @override
  String get dating_setUpLater => 'Set up later';

  @override
  String get dating_justMeDone => 'You\'re on \'Just for me\'.';

  @override
  String get dating_undo => 'Undo';

  @override
  String get dating_lookingTitle => 'What are you looking for?';

  @override
  String get dating_intentMarriage => 'Marriage';

  @override
  String get dating_intentCommitted => 'A committed relationship';

  @override
  String get dating_intentCompanionship => 'Companionship, at my own pace';

  @override
  String get dating_intentNotSure => 'Not sure yet';

  @override
  String get dating_timelineQ => 'When would you like to marry?';

  @override
  String get dating_timelineSoon => 'In the next year or two';

  @override
  String get dating_timelineFew => 'In a few years';

  @override
  String get dating_timelineNone => 'No set time';

  @override
  String get dating_timelineShow => 'Show this on my profile';

  @override
  String get dating_attestation => 'I\'m not married in any form (customary, religious or civil), I\'m not separated from a spouse, and I\'m not in a relationship.';

  @override
  String get dating_attestationHelper => 'Dating on Attune is for people who are free to start a relationship.';

  @override
  String get dating_attestationError => 'Please confirm you\'re free to start a relationship.';

  @override
  String get dating_separatedLink => 'I\'m separated but not divorced';

  @override
  String get dating_separatedSheet => 'Dating isn\'t open to you yet. Once your divorce is final, you\'re welcome here. Attune just for me is open to you now.';

  @override
  String get dating_marriedBefore => 'Married before? (optional)';

  @override
  String get dating_maritalNever => 'Never';

  @override
  String get dating_maritalDivorced => 'Divorced';

  @override
  String get dating_maritalWidowed => 'Widowed';

  @override
  String get dating_maritalShow => 'Show on my profile';

  @override
  String get dating_whereTitle => 'Where are you?';

  @override
  String get dating_countryLabel => 'Country';

  @override
  String get dating_regionLabel => 'Region';

  @override
  String get dating_countryNotListed => 'My country isn\'t listed';

  @override
  String dating_regionClosed(String regions) {
    return 'Dating is open in $regions for now. We\'re opening other regions as soon as we can look after them well.';
  }

  @override
  String dating_sideLabel(String region) {
    return 'Which side of $region? (optional)';
  }

  @override
  String get dating_sideEither => 'Either side';

  @override
  String get dating_scopeQ => 'How far would you like to meet people?';

  @override
  String get dating_scopeSide => 'My side';

  @override
  String get dating_scopeRegion => 'My region';

  @override
  String dating_scopeCountry(String country) {
    return 'Anywhere in $country';
  }

  @override
  String get dating_abroadRow => 'Also open to people in other countries';

  @override
  String get dating_abroadDisabled => 'Available once you\'re verified and your account is 14 days old.';

  @override
  String get dating_whereHelper => 'We never use your exact location. Others see your region only.';

  @override
  String get dating_search => 'Search';

  @override
  String get dating_choose => 'Choose';

  @override
  String get dating_privacyTitle => 'Your answers stay private';

  @override
  String get dating_privacyWhyHead => 'Why we ask';

  @override
  String get dating_privacyWhoHead => 'Who sees what';

  @override
  String get dating_privacyNeverHead => 'What we never do';

  @override
  String get dating_privacyProtectedHead => 'How it\'s protected';

  @override
  String get dating_privacyLeavingHead => 'Leaving';

  @override
  String get dating_privacyWhy => 'The next questions are about you and who you\'d like to meet. We use your answers only to introduce you to people who\'d like to meet you too.';

  @override
  String get dating_privacyWho => 'Nobody ever sees who you\'d like to meet. Your gender, faith and marriage history appear on your profile only if you choose. We never collect your exact location.';

  @override
  String get dating_privacyNever => 'Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.';

  @override
  String get dating_privacyProtected => 'These answers are stored encrypted. The people who review reports can\'t see them.';

  @override
  String get dating_privacyLeaving => 'You can leave Dating at any time, and these answers are deleted.';

  @override
  String get dating_privacyConsent => 'I agree that Attune can use my answers about my gender and who I\'d like to meet to introduce me.';

  @override
  String get dating_datingTerms => 'Dating terms';

  @override
  String get dating_privacyNotice => 'Privacy notice';

  @override
  String get dating_agreeContinue => 'Agree and continue';

  @override
  String get dating_youTitle => 'Which best describes you?';

  @override
  String get dating_identityWoman => 'Woman';

  @override
  String get dating_identityMan => 'Man';

  @override
  String get dating_identityNonBinary => 'Non-binary';

  @override
  String get dating_moreSpecific => 'Add something more specific';

  @override
  String get dating_specificTransWoman => 'Trans woman';

  @override
  String get dating_specificTransMan => 'Trans man';

  @override
  String get dating_specificGenderfluid => 'Genderfluid';

  @override
  String get dating_specificGenderqueer => 'Genderqueer';

  @override
  String get dating_specificAgender => 'Agender';

  @override
  String get dating_specificIntersex => 'Intersex';

  @override
  String get dating_specificOwnWords => 'In my own words';

  @override
  String get dating_specificInvalid => 'Use letters, spaces and hyphens only, up to 30.';

  @override
  String get dating_nbPoolsQ => 'Should we also introduce you to people looking for:';

  @override
  String get dating_poolWomen => 'Women';

  @override
  String get dating_poolMen => 'Men';

  @override
  String get dating_nbPoolsHelper => 'People open to everyone can always be introduced to you.';

  @override
  String get dating_pronouns => 'Pronouns (optional)';

  @override
  String get dating_genderShow => 'Show my gender on my profile';

  @override
  String get dating_youHelper => 'We use this only to introduce you to people who want to meet someone like you.';

  @override
  String dating_offCountryLine(String country) {
    return 'In $country, Dating introduces men and women to each other for now. If neither of these fits you, Dating can\'t introduce you safely here yet.';
  }

  @override
  String get dating_supportForYou => 'Support for you';

  @override
  String get dating_meetTitle => 'Who would you like to meet?';

  @override
  String get dating_seekMen => 'Men';

  @override
  String get dating_seekWomen => 'Women';

  @override
  String get dating_seekEveryone => 'Everyone';

  @override
  String get dating_meetPrivate => 'Only you can see this. It\'s never on your profile.';

  @override
  String get dating_offMeetMen => 'You\'ll be introduced to men.';

  @override
  String get dating_offMeetWomen => 'You\'ll be introduced to women.';

  @override
  String dating_offMeetLine(String country) {
    return 'In $country, Attune introduces men and women to each other for now.';
  }

  @override
  String dating_ages(int min, int max) {
    return 'Ages $min to $max';
  }

  @override
  String dating_agesYoungest(int age) {
    return 'Youngest $age';
  }

  @override
  String dating_agesOldest(int age) {
    return 'Oldest $age';
  }

  @override
  String get dating_noteTitle => 'Before you save this';

  @override
  String dating_notePhone(String country) {
    return 'Your phone number is from $country, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know.';
  }

  @override
  String get dating_noteThen => 'Attune never shows who you\'d like to meet, never shows distance, and keeps Dating out of your notifications. You can also set a PIN, use a plain app icon, and leave Dating at any time to delete these answers.';

  @override
  String get dating_noteSave => 'Save';

  @override
  String get dating_noteSetPin => 'Set a PIN first';

  @override
  String get dating_noteBack => 'Go back';

  @override
  String get dating_childrenTitle => 'Children';

  @override
  String get dating_childrenHaveQ => 'Do you have children?';

  @override
  String get dating_yes => 'Yes';

  @override
  String get dating_no => 'No';

  @override
  String get dating_childrenWantQ => 'Do you want children (or more children)?';

  @override
  String get dating_openToIt => 'Open to it';

  @override
  String get dating_childrenMustMatch => 'Only introduce me to people whose answer fits mine';

  @override
  String get dating_childrenExcludeParents => 'I\'d rather not meet people who have children';

  @override
  String get dating_childrenHelper => 'We never ask for your children\'s names or ages, and photos with children can\'t be used.';

  @override
  String get dating_faithTitle => 'Faith';

  @override
  String get dating_optional => 'Optional';

  @override
  String get dating_denomination => 'Denomination (optional)';

  @override
  String get dating_importanceQ => 'How much does sharing a faith matter to you?';

  @override
  String get dating_importanceNo => 'It doesn\'t matter';

  @override
  String get dating_importanceNice => 'Nice if we share';

  @override
  String get dating_importanceMust => 'We must share it';

  @override
  String get dating_faithShow => 'Show my faith on my profile';

  @override
  String get dating_faithConsent => 'Faith is sensitive information. I agree that Attune can use it to introduce me.';

  @override
  String get dating_faithConsentError => 'Please agree, or choose Skip.';

  @override
  String get dating_agesYoungestLabel => 'Youngest';

  @override
  String get dating_agesOldestLabel => 'Oldest';

  @override
  String get dating_photosTitle => 'Add your photos';

  @override
  String get dating_photosBody => 'Add 2 to 6 photos. Clear, recent photos of just you work best.';

  @override
  String get dating_photoAdd => 'Add photo';

  @override
  String dating_photoPreparing(int n) {
    return 'Preparing photo $n…';
  }

  @override
  String dating_photoUploading(int n) {
    return 'Uploading photo $n…';
  }

  @override
  String get dating_photoChecking => 'Checking…';

  @override
  String get dating_photoReady => 'Ready';

  @override
  String get dating_photoReview => 'Needs a person to check it. That usually takes less than a day.';

  @override
  String dating_photoFaceUnclear(int n) {
    return 'Photo $n: we couldn\'t see your face clearly.';
  }

  @override
  String dating_photoTooSmall(int n) {
    return 'Photo $n is too small.';
  }

  @override
  String dating_photoChild(int n) {
    return 'Photo $n: photos with children can\'t be used on Dating. Crop to just you?';
  }

  @override
  String get dating_photoCrop => 'Crop';

  @override
  String dating_photoCantUse(int n) {
    return 'Photo $n can\'t be used.';
  }

  @override
  String dating_photoFailed(int n) {
    return 'Photo $n didn\'t upload. Try again.';
  }

  @override
  String dating_photoSlot(int n, String state) {
    return 'Photo $n of 6, $state';
  }

  @override
  String get dating_photoMoveEarlier => 'Move earlier';

  @override
  String get dating_photoMoveLater => 'Move later';

  @override
  String get dating_photoRemove => 'Remove';

  @override
  String get dating_photoReplace => 'Replace';

  @override
  String get dating_photoCaption => 'Add a caption (only you see it)';

  @override
  String get dating_photoCaptionLabel => 'Caption';

  @override
  String get dating_photoSave => 'Save';

  @override
  String get dating_photosAfterMutual => 'Show my photos only after we\'re both interested';

  @override
  String dating_photosAfterMutualFrom(String date) {
    return 'Available from $date. New accounts show their photos for the first 30 days, which helps stop fake profiles.';
  }

  @override
  String get dating_photosData => 'Each photo uses about 300 KB.';

  @override
  String get dating_photosOffline => 'You\'re offline. Add photos when you\'re connected.';

  @override
  String get dating_promptsTitle => 'A little about you';

  @override
  String get dating_promptsBody => 'Answer 2 of these. Short is fine.';

  @override
  String get dating_prompt_perfect_sunday => 'A perfect Sunday for me looks like…';

  @override
  String get dating_prompt_feel_at_home => 'I feel most at home when…';

  @override
  String get dating_prompt_friends_say => 'My friends would say I\'m…';

  @override
  String get dating_prompt_looking_for => 'I\'m looking for someone who…';

  @override
  String get dating_prompt_small_thing => 'A small thing that makes my day…';

  @override
  String get dating_prompt_win_me_over => 'The way to win me over is…';

  @override
  String get dating_prompt_learning_to => 'I\'m learning to…';

  @override
  String get dating_prompt_family_describe => 'My family would describe me as…';

  @override
  String get dating_prompt_place_love => 'A kind of place I love spending time…';

  @override
  String get dating_prompt_ask_me_about => 'Ask me about…';

  @override
  String get dating_promptTooShort => 'At least 10 characters.';

  @override
  String dating_photoPickFailed(int n) {
    return 'Photo $n: your photos couldn\'t be opened. Check that Attune can use them in Settings, then try again.';
  }

  @override
  String dating_photoCropFailed(int n) {
    return 'Photo $n couldn\'t be cropped. Try again.';
  }

  @override
  String get dating_textInvisible => 'Some emoji and symbols can\'t be used here. Try taking them out.';

  @override
  String get dating_promptNeedsWords => 'Add a few words, not just emoji or symbols.';

  @override
  String get dating_verifyTitle => 'Verify it\'s you';

  @override
  String get dating_verifyBody => 'A short video selfie checks that you\'re a real person, that your photos are you, and that you\'re over 18. The video is deleted at once. We keep only whether it passed.';

  @override
  String get dating_verifyLater => 'You\'ll do this check before your first introduction.';

  @override
  String get dating_previewTitle => 'This is what others see';

  @override
  String get dating_previewNever => 'Never shown: who you\'d like to meet, your exact location, your date of birth.';

  @override
  String get dating_previewUnavailable => 'Your preview can\'t be shown right now.';

  @override
  String get dating_tryAgain => 'Try again';

  @override
  String get dating_nameLabel => 'First name';

  @override
  String get dating_nameHelper => 'Use your first name or what friends call you.';

  @override
  String get dating_nameInvalid => 'Use 1 to 30 characters.';

  @override
  String get dating_save => 'Save';

  @override
  String get dating_editName => 'Edit first name';

  @override
  String get dating_editLooking => 'Edit what you\'re looking for';

  @override
  String get dating_editWhere => 'Edit where you are';

  @override
  String get dating_editPrompts => 'Edit your answers';

  @override
  String get dating_editChildren => 'Edit children';

  @override
  String get dating_editAbout => 'Edit what you show about yourself';

  @override
  String get dating_editPhotos => 'Edit photos';

  @override
  String get dating_pushDigest => 'Tell me about new introductions and matches, at most once a day.';

  @override
  String get dating_pushTurnOn => 'Turn on';

  @override
  String get dating_pushDigestOn => 'We\'ll tell you about new introductions and matches, at most once a day.';

  @override
  String get dating_pushMessages => 'Tell me when someone messages me';

  @override
  String dating_cardHeading(String name, int age) {
    return '$name, $age';
  }

  @override
  String get dating_cardMarriage => 'Looking for marriage';

  @override
  String get dating_cardMarriageSoon => 'Looking for marriage, in the next year or two';

  @override
  String get dating_cardMarriageFew => 'Looking for marriage, in a few years';

  @override
  String get dating_cardMarriageNone => 'Looking for marriage, with no set time';

  @override
  String get dating_cardCommitted => 'Looking for a committed relationship';

  @override
  String get dating_cardCompanionship => 'Looking for companionship, at a comfortable pace';

  @override
  String get dating_cardNotSure => 'Not sure yet';

  @override
  String get dating_cardHasChildren => 'Has children';

  @override
  String get dating_cardNoChildren => 'No children';

  @override
  String get dating_cardWantsChildren => 'Wants children';

  @override
  String get dating_cardNoWantChildren => 'Doesn\'t want children';

  @override
  String get dating_cardOpenChildren => 'Open to children';

  @override
  String get dating_cardPhotosLater => 'Photos appear after you\'re both interested.';

  @override
  String get dating_cardShowPhotos => 'Show photos (about 1 MB)';

  @override
  String dating_cardPhoto(int n, int count) {
    return 'Photo $n of $count';
  }

  @override
  String get dating_readyTitle => 'You\'re all set';

  @override
  String dating_readyFirst(String date, String time) {
    return 'Your first introductions arrive $date at $time.';
  }

  @override
  String get dating_readyChangeTime => 'Change time';

  @override
  String get dating_readyTimeTitle => 'Pick a time when you have a few quiet minutes.';

  @override
  String get dating_readyWhile => 'While you wait';

  @override
  String get dating_readyJournal => 'Write in your journal';

  @override
  String get dating_readySharedQ => 'Does anyone else use this phone?';

  @override
  String get dating_readyLock => 'Lock Dating with your PIN';

  @override
  String get dating_readyEveryOpen => 'Ask for my PIN every time Attune opens';

  @override
  String get dating_done => 'Done';

  @override
  String get dating_readyGates => 'We still need to check it\'s you before introductions start.';

  @override
  String get dating_editFaith => 'Edit faith';

  @override
  String get dating_editMarital => 'Edit marital status';

  @override
  String dating_cardPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get dating_settingsTime => 'Introduction time';

  @override
  String get dating_settingsWho => 'Who I\'d like to meet';

  @override
  String get dating_settingsAges => 'Ages';

  @override
  String dating_settingsAgesValue(int min, int max) {
    return '$min to $max';
  }

  @override
  String get dating_settingsHowFar => 'How far';

  @override
  String get dating_settingsPhotosAfter => 'Photos after mutual interest';

  @override
  String get dating_settingsDataSaver => 'Data saver';

  @override
  String get dating_settingsDataSaverSub => 'Show photos only when I tap';

  @override
  String get dating_settingsNotifications => 'Notifications';

  @override
  String get dating_settingsPause => 'Pause Dating';

  @override
  String get dating_pausedLine => 'Dating is paused. Nobody new sees you, and your conversations stay open.';

  @override
  String get dating_settingsResume => 'Resume Dating';

  @override
  String get dating_settingsLeave => 'Leave Dating and delete my data';

  @override
  String get dating_leaveTitle => 'Leave Dating?';

  @override
  String get dating_leaveNow => 'Deleted now: your Dating profile, photos, prompts, who you\'d like to meet, your gender and faith answers, your settings and your private notes.';

  @override
  String get dating_leave30 => 'Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.';

  @override
  String get dating_leaveSafety => 'Kept for safety, for up to 2 years, only if your account is restricted or you\'ve blocked someone: a code made from your phone number, never the number itself.';

  @override
  String get dating_leaveRecord => 'Kept as a record: when you agreed to Dating\'s terms and when you left.';

  @override
  String get dating_leaveKeepList => 'Keep my \'Never introduce me\' list in case I come back. It holds codes, not numbers.';

  @override
  String get dating_leaveConfirm => 'Leave and delete';

  @override
  String get dating_leavePause => 'Pause instead';

  @override
  String get dating_leftDone => 'You\'ve left Dating. You can set it up again any time.';

  @override
  String get dating_leftSuspended => 'You\'ve left Dating.';

  @override
  String dating_photoRemoveQ(int n) {
    return 'Remove photo $n?';
  }

  @override
  String get dating_photoRemoveBody => 'It\'s deleted at once. A photo you add later is checked again before anyone sees it.';

  @override
  String get dating_photoKeep => 'Keep it';
}
