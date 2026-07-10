// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TranslationRegistry
 * @dev A smart contract to store and verify translations on-chain.
 * Perfect for BHARAT KI AWAAZ offline-to-online translation logging.
 */
contract TranslationRegistry {
    
    struct Translation {
        address sender;
        string originalText;
        string translatedText;
        uint256 timestamp;
    }

    // List of all translations recorded on-chain
    Translation[] private translations;

    // Mapping of user address to their recorded translations
    mapping(address => Translation[]) private userTranslations;

    // Emitted when a translation is successfully recorded on-chain
    event TranslationRecorded(
        address indexed sender,
        uint256 indexed index,
        string originalText,
        string translatedText,
        uint256 timestamp
    );

    /**
     * @dev Records a translation on the blockchain
     * @param _originalText The source text
     * @param _translatedText The translated output
     */
    function recordTranslation(
        string calldata _originalText,
        string calldata _translatedText
    ) external {
        require(bytes(_originalText).length > 0, "Original text cannot be empty");
        require(bytes(_translatedText).length > 0, "Translated text cannot be empty");

        Translation memory newTranslation = Translation({
            sender: msg.sender,
            originalText: _originalText,
            translatedText: _translatedText,
            timestamp: block.timestamp
        });

        translations.push(newTranslation);
        userTranslations[msg.sender].push(newTranslation);

        emit TranslationRecorded(
            msg.sender,
            translations.length - 1,
            _originalText,
            _translatedText,
            block.timestamp
        );
    }

    /**
     * @dev Retrieves all translations recorded on-chain
     */
    function getAllTranslations() external view returns (Translation[] memory) {
        return translations;
    }

    /**
     * @dev Retrieves translations recorded by a specific sender
     * @param _user The address of the user
     */
    function getUserTranslations(address _user) external view returns (Translation[] memory) {
        return userTranslations[_user];
    }

    /**
     * @dev Retrieves total count of recorded translations
     */
    function getTranslationCount() external view returns (uint256) {
        return translations.length;
    }
}
