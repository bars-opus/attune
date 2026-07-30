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
    return 'Você está navegando $appName como convidado. Faça login ou crie uma conta para começar a gerenciar sua loja – leva menos de 5 segundos. Temos uma variedade de ferramentas para ajudar a crescer seu negócio, tudo gratuitamente.';
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
  String get mutedItemSubtitle =>
      'Contas anônimas do fórum que você silenciou';

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
  String emptyStateNoDataTitle(String dataType) {
    return 'Nenhum(a) $dataType ainda';
  }

  @override
  String emptyStateNoDataSubtitle(String dataType) {
    return 'Quando $dataType estiver disponível, aparecerão aqui.';
  }

  @override
  String get emptyStateNoResultsTitle => 'Nenhum resultado encontrado';

  @override
  String emptyStateNoResultsSubtitle(String dataType) {
    return 'Tente ajustar sua pesquisa ou filtros para encontrar $dataType.';
  }

  @override
  String get emptyStateNoInternetTitle => 'Sem conexão com a internet';

  @override
  String get emptyStateNoInternetSubtitle => 'Verifique sua conexão e tente novamente.';

  @override
  String get emptyStateNoFavoritesTitle => 'Nenhum favorito ainda';

  @override
  String get emptyStateNoFavoritesSubtitle => 'Comece adicionando itens à sua lista de favoritos.';

  @override
  String get emptyStateNoMessagesTitle => 'Nenhuma mensagem';

  @override
  String get emptyStateNoMessagesSubtitle => 'Inicie uma conversa para ver mensagens aqui.';

  @override
  String get emptyStateRefresh => 'Atualizar';

  @override
  String get emptyStateClearFilters => 'Limpar filtros';

  @override
  String get emptyStateRetry => 'Tentar novamente';

  @override
  String get emptyStateExplore => 'Explorar';

  @override
  String get emptyStateStartChat => 'Iniciar chat';

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
  String get dataTypeUsers => 'usuários';

  @override
  String get dataTypeUser => 'usuário';

  @override
  String get dataTypeProducts => 'produtos';

  @override
  String get dataTypeProduct => 'produto';

  @override
  String get dataTypeOrders => 'pedidos';

  @override
  String get dataTypeOrder => 'pedido';

  @override
  String get dataTypeMessages => 'mensagens';

  @override
  String get dataTypeMessage => 'mensagem';

  @override
  String get dataTypeFavorites => 'favoritos';

  @override
  String get dataTypeFavorite => 'favorito';

  @override
  String get dataTypeData => 'dados';

  @override
  String get dataTypeContent => 'conteúdo';

  @override
  String get dataTypeItems => 'itens';

  @override
  String get dataTypeItem => 'item';

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
}
