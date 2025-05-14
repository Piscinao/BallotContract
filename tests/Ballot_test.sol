// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
import "hardhat/console.sol";
import "../contracts/3_Ballot.sol";

/**
 * @title Testes do Contrato de Votação
 * @dev Demonstra boas práticas de teste em contratos inteligentes
 *
 * Conceitos importantes de testes em blockchain:
 * 1. Isolamento: Cada teste deve ser independente
 * 2. Estado inicial: Sempre comece com um estado conhecido
 * 3. Manipulação de tempo: Simule diferentes momentos da blockchain
 * 4. Verificação de eventos: Teste a emissão correta de eventos
 * 5. Simulação de diferentes endereços: Teste diferentes perfis de usuário
 */
contract BallotTest {
    // Variáveis de estado para os testes
    bytes32[] proposalNames;
    string[] proposalDescriptions;
    Ballot ballotToTest;
    address voter1;
    address voter2;
    
    // Eventos para teste - espelho dos eventos do contrato
    event VoterRegistered(address indexed voter);
    event VoteCast(address indexed voter, bytes32 secretHash);
    
    /**
     * @dev Setup inicial dos testes
     * 
     * Conceitos demonstrados:
     * - Preparação do ambiente de teste
     * - Criação de dados de teste
     * - Implantação de contrato em ambiente de teste
     */
    function beforeAll() public {
        // Setup das propostas com dados de teste
        proposalNames.push(bytes32("candidate1"));
        proposalNames.push(bytes32("candidate2"));
        proposalDescriptions.push("Descricao do candidato 1");
        proposalDescriptions.push("Descricao do candidato 2");
        
        // Criação de endereços de teste
        // Na blockchain real, seriam endereços de carteiras
        voter1 = address(0x1234);
        voter2 = address(0x5678);
        
        // Deploy do contrato com parâmetros de teste
        ballotToTest = new Ballot(proposalNames, proposalDescriptions, 3600, 1800);
    }
    
    /**
     * @dev Teste de inicialização
     * 
     * Conceitos demonstrados:
     * - Verificação de estado inicial
     * - Teste de propriedades imutáveis
     * - Verificação de status
     */
    function checkInitialization() public {
        Assert.equal(ballotToTest.chairperson(), address(this), "Chairperson deveria ser o criador do contrato");
        Assert.equal(ballotToTest.getVotingStatus(), uint8(0), "Status inicial deveria ser votacao em andamento");
    }
    
    /**
     * @dev Teste de registro de votantes
     * 
     * Conceitos demonstrados:
     * - Modificação de estado
     * - Verificação de permissões
     * - Leitura de estruturas complexas
     */
    function checkVoterRegistration() public {
        ballotToTest.giveRightToVote(voter1);
        (uint256 weight,,,,, ) = ballotToTest.voters(voter1);
        Assert.equal(weight, uint256(1), "Peso do voto deveria ser 1 apos registro");
    }
    
    /**
     * @dev Teste de votação secreta
     * 
     * Conceitos demonstrados:
     * - Criptografia na blockchain (keccak256)
     * - Simulação de diferentes endereços (vm.prank)
     * - Verificação de estado após transação
     */
    function checkSecretVoting() public {
        // Registro do votante
        ballotToTest.giveRightToVote(voter2);
        
        // Demonstração de criação de hash na blockchain
        bytes32 salt = bytes32(uint256(123));
        uint256 proposal = 0;
        bytes32 voteHash = keccak256(abi.encodePacked(proposal, salt));
        
        // Simulação de chamada de outro endereço
        vm.prank(voter2);
        ballotToTest.castSecretVote(voteHash);
        
        // Verificação do estado após a transação
        (,bool voted,,,bytes32 secretHash,) = ballotToTest.voters(voter2);
        Assert.equal(voted, true, "Votante deveria estar marcado como tendo votado");
        Assert.equal(secretHash, voteHash, "Hash do voto secreto deveria estar registrado");
    }
    
    /**
     * @dev Teste de cancelamento de voto
     * 
     * Conceitos demonstrados:
     * - Reversão de estado
     * - Múltiplas transações
     * - Verificação de limpeza de estado
     */
    function checkVoteCancellation() public {
        // Setup e votação
        address voter3 = address(0x9ABC);
        ballotToTest.giveRightToVote(voter3);
        
        bytes32 voteHash = keccak256(abi.encodePacked(uint256(0), bytes32(uint256(456))));
        vm.prank(voter3);
        ballotToTest.castSecretVote(voteHash);
        
        // Cancelamento e verificação
        vm.prank(voter3);
        ballotToTest.cancelVote();
        
        // Verificação de limpeza de estado
        (,bool voted,,,bytes32 secretHash,) = ballotToTest.voters(voter3);
        Assert.equal(voted, false, "Voto deveria estar cancelado");
        Assert.equal(secretHash, bytes32(0), "Hash do voto deveria estar limpo");
    }
    
    /**
     * @dev Teste de revelação de voto
     * 
     * Conceitos demonstrados:
     * - Manipulação de tempo na blockchain
     * - Fases do contrato
     * - Verificação de transição de estado
     */
    function checkVoteReveal() public {
        // Manipulação de tempo na blockchain de teste
        vm.warp(block.timestamp + 3601); // Avança para fase de revelação
        
        // Revelação do voto
        bytes32 salt = bytes32(uint256(123));
        vm.prank(voter2);
        ballotToTest.revealVote(0, salt);
        
        // Verificação do estado final
        (,,,,,bool revealed) = ballotToTest.voters(voter2);
        Assert.equal(revealed, true, "Voto deveria estar revelado");
    }
    
    /**
     * @dev Teste do resultado final
     * 
     * Conceitos demonstrados:
     * - Estado final do contrato
     * - Múltiplas verificações
     * - Funções view
     */
    function checkFinalResult() public {
        // Avanço do tempo para fim da votação
        vm.warp(block.timestamp + 1801);
        
        // Verificações múltiplas do resultado
        Assert.equal(ballotToTest.winningProposal(), uint256(0), "Proposta 0 deveria ser a vencedora");
        Assert.equal(ballotToTest.winnerName(), bytes32("candidate1"), "Candidate1 deveria ser o vencedor");
        Assert.equal(ballotToTest.winnerDescription(), "Descricao do candidato 1", "Descricao do vencedor incorreta");
    }
}