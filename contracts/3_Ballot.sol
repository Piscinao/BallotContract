// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/** 
 * @title Enhanced Ballot
 * @dev Implementa um processo de votação seguro e transparente na blockchain
 * 
 * Este contrato demonstra vários conceitos importantes da blockchain:
 * 1. Imutabilidade: Uma vez que um voto é registrado e revelado, não pode ser alterado
 * 2. Transparência: Todas as ações são registradas publicamente através de eventos
 * 3. Descentralização: Não há uma autoridade central controlando os votos
 * 4. Consenso: O resultado é determinado automaticamente baseado nas regras do contrato
 */
contract Ballot {
    // Estruturas de dados armazenadas permanentemente na blockchain
    struct Voter {
        uint256 weight;           // peso do voto (acumulado por delegação)
        bool voted;              // se já votou
        address delegate;        // pessoa para quem delegou
        uint256 vote;           // índice da proposta votada
        bytes32 secretHash;     // hash do voto secreto (usando criptografia na blockchain)
        bool hasRevealedVote;   // se já revelou o voto secreto
    }

    // As propostas também são armazenadas permanentemente na blockchain
    struct Proposal {
        bytes32 name;           // nome curto (até 32 bytes para otimizar gas)
        uint256 voteCount;      // número de votos acumulados
        string description;     // descrição detalhada (armazenada como string dinâmica)
    }

    // Variáveis de estado - Armazenadas permanentemente no storage da blockchain
    // 'immutable' significa que não pode ser alterado após a implantação, economizando gas
    address public immutable chairperson;
    
    // Timestamps da blockchain são usados para controle temporal
    uint256 public votingEndTime;    // Timestamp do fim da votação
    uint256 public revealEndTime;    // Timestamp do fim da fase de revelação
    bool public votingEnded;
    
    // Mapping: estrutura especial da blockchain que mapeia endereços a dados
    mapping(address => Voter) public voters;
    // Array dinâmico: pode crescer, mas aumenta o custo de gas
    Proposal[] public proposals;
    
    // Eventos: permitem rastreamento eficiente de ações na blockchain
    // 'indexed' permite filtrar eventos específicos (até 3 por evento)
    event VotingStarted(uint256 endTime);
    event VoterRegistered(address indexed voter);
    event VoteDelegated(address indexed from, address indexed to);
    event VoteCast(address indexed voter, bytes32 secretHash);
    event VoteRevealed(address indexed voter, uint256 proposal);
    event VoteCancelled(address indexed voter);
    event VotingEnded(uint256 winningProposal);

    // Modificadores: reduzem código duplicado e aumentam segurança
    modifier onlyChairperson() {
        // msg.sender é uma variável global que representa o endereço que chamou a função
        require(msg.sender == chairperson, "Apenas o presidente pode executar esta acao");
        _;
    }

    // block.timestamp é o timestamp atual do bloco na blockchain
    modifier votingOpen() {
        require(block.timestamp < votingEndTime, "Votacao encerrada");
        _;
    }

    modifier revealPhase() {
        require(block.timestamp >= votingEndTime && block.timestamp < revealEndTime, "Fora da fase de revelacao");
        _;
    }

    /** 
     * @dev Constructor: executado apenas uma vez na implantação do contrato
     * 
     * Conceitos blockchain demonstrados:
     * - Implantação de contrato
     * - Inicialização de estado
     * - Gas cost: arrays maiores = maior custo
     * - Timestamp blockchain
     */
    constructor(
        bytes32[] memory proposalNames,      // array na memory (temporário)
        string[] memory descriptions,        // strings são mais caras em gas
        uint256 votingPeriod,               // duração em segundos
        uint256 revealPeriod                // período de revelação
    ) {
        require(proposalNames.length == descriptions.length, "Numero de nomes e descricoes deve ser igual");
        require(votingPeriod > 0 && revealPeriod > 0, "Periodos devem ser maiores que zero");
        
        // msg.sender no constructor é quem está implantando o contrato
        chairperson = msg.sender;
        voters[chairperson].weight = 1;
        
        // Loop aumenta o custo de gas proporcionalmente ao número de propostas
        for (uint256 i = 0; i < proposalNames.length; i++) {
            proposals.push(Proposal({
                name: proposalNames[i],
                voteCount: 0,
                description: descriptions[i]
            }));
        }
        
        // block.timestamp é o timestamp do bloco atual
        votingEndTime = block.timestamp + votingPeriod;
        revealEndTime = votingEndTime + revealPeriod;
        
        emit VotingStarted(votingEndTime);
    }

    /** 
     * @dev Registra um novo votante
     * 
     * Conceitos blockchain demonstrados:
     * - Controle de acesso (onlyChairperson)
     * - Modificação de estado
     * - Eventos para rastreabilidade
     * - Validação de endereços
     */
    function giveRightToVote(address voter) external onlyChairperson votingOpen {
        require(voter != address(0), "Endereco invalido");
        require(!voters[voter].voted, "Votante ja votou");
        require(voters[voter].weight == 0, "Votante ja tem direito ao voto");
        
        voters[voter].weight = 1;
        emit VoterRegistered(voter);
    }

    /**
     * @dev Sistema de delegação de votos
     * 
     * Conceitos blockchain demonstrados:
     * - Delegação de direitos
     * - Prevenção de loops infinitos (gas limit)
     * - Storage vs Memory
     * - Acumulação de peso dos votos
     */
    function delegate(address to) external votingOpen {
        require(to != address(0), "Endereco invalido");
        // storage: referência direta ao estado do contrato
        Voter storage sender = voters[msg.sender];
        
        require(sender.weight != 0, "Sem direito a voto");
        require(!sender.voted, "Ja votou");
        require(to != msg.sender, "Auto-delegacao nao permitida");
        
        // Loop potencialmente perigoso - limitado pelo gas
        while (voters[to].delegate != address(0)) {
            to = voters[to].delegate;
            require(to != msg.sender, "Loop de delegacao detectado");
        }
        
        Voter storage delegate_ = voters[to];
        require(delegate_.weight >= 1, "Delegado sem direito a voto");
        
        sender.voted = true;
        sender.delegate = to;
        
        if (delegate_.voted) {
            proposals[delegate_.vote].voteCount += sender.weight;
        } else {
            delegate_.weight += sender.weight;
        }
        
        emit VoteDelegated(msg.sender, to);
    }

    /**
     * @dev Sistema de votação secreta usando hash
     * 
     * Conceitos blockchain demonstrados:
     * - Criptografia na blockchain (keccak256)
     * - Commit-reveal pattern
     * - Privacidade vs Transparência
     * - Otimização de gas com bytes32
     */
    function castSecretVote(bytes32 secretHash) external votingOpen {
        Voter storage sender = voters[msg.sender];
        require(sender.weight != 0, "Sem direito a voto");
        require(!sender.voted, "Ja votou");
        require(secretHash != 0, "Hash invalido");
        
        sender.secretHash = secretHash;
        sender.voted = true;
        
        emit VoteCast(msg.sender, secretHash);
    }

    /**
     * @dev Revelação do voto secreto
     * 
     * Conceitos blockchain demonstrados:
     * - Verificação de hash na blockchain
     * - Fases temporais controladas por timestamp
     * - Validação de dados off-chain/on-chain
     */
    function revealVote(uint256 proposal, bytes32 salt) external revealPhase {
        Voter storage sender = voters[msg.sender];
        require(sender.voted && !sender.hasRevealedVote, "Voto ja revelado ou nao registrado");
        require(proposal < proposals.length, "Proposta invalida");
        
        // Recalcula o hash para verificar se corresponde ao registrado
        bytes32 computedHash = keccak256(abi.encodePacked(proposal, salt));
        require(computedHash == sender.secretHash, "Hash nao corresponde");
        
        sender.hasRevealedVote = true;
        sender.vote = proposal;
        proposals[proposal].voteCount += sender.weight;
        
        emit VoteRevealed(msg.sender, proposal);
    }

    /**
     * @dev Cancelamento de voto não revelado
     * 
     * Conceitos blockchain demonstrados:
     * - Reversão de estado
     * - Limitações de modificação
     * - Economia de gas (zerando valores)
     */
    function cancelVote() external votingOpen {
        Voter storage sender = voters[msg.sender];
        require(sender.voted && !sender.hasRevealedVote, "Voto nao pode ser cancelado");
        
        sender.voted = false;
        sender.secretHash = 0;  // Economiza gas zerando o valor
        
        emit VoteCancelled(msg.sender);
    }

    /**
     * @dev Cálculo da proposta vencedora
     * 
     * Conceitos blockchain demonstrados:
     * - Funções view (não modificam estado)
     * - Iteração em arrays (custo de gas)
     * - Leitura de estado
     */
    function winningProposal() public view returns (uint256 winningProposal_) {
        require(block.timestamp >= revealEndTime, "Votacao ainda nao encerrada");
        uint256 winningVoteCount = 0;
        
        // Loop sobre array: custoso em gas, mas é view
        for (uint256 p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
                winningProposal_ = p;
            }
        }
    }

    /**
     * @dev Retorna o nome do vencedor
     * 
     * Conceitos blockchain demonstrados:
     * - Retorno de tipos fixos (bytes32)
     * - Composição de funções
     */
    function winnerName() external view returns (bytes32 winnerName_) {
        winnerName_ = proposals[winningProposal()].name;
    }

    /**
     * @dev Retorna a descrição do vencedor
     * 
     * Conceitos blockchain demonstrados:
     * - Retorno de strings (tipo dinâmico)
     * - Uso de memory para tipos dinâmicos
     */
    function winnerDescription() external view returns (string memory description) {
        description = proposals[winningProposal()].description;
    }

    /**
     * @dev Status atual da votação
     * 
     * Conceitos blockchain demonstrados:
     * - Enums na blockchain
     * - Timestamps e controle temporal
     * - Funções view para consulta
     */
    function getVotingStatus() external view returns (uint8 status) {
        if (block.timestamp < votingEndTime) {
            return 0; // Votação em andamento
        } else if (block.timestamp < revealEndTime) {
            return 1; // Fase de revelação
        } else {
            return 2; // Encerrada
        }
    }
}