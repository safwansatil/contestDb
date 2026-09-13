import { useState } from 'react'
import { Chess } from 'chess.js'
import { Chessboard } from 'react-chessboard'

export function ChessSubmissionUI({
  onMove
}: {
  onMove: (pgn: string, fen?: string, move?: string) => void
}) {
  const [game, setGame] = useState(new Chess())
  const [lastMove, setLastMove] = useState<string | undefined>()

  function makeRandomMove(currentGame: Chess) {
    const possibleMoves = currentGame.moves()

    if (
      currentGame.isGameOver() ||
      currentGame.isDraw() ||
      possibleMoves.length === 0
    ) {
      return
    }

    const randomIndex = Math.floor(Math.random() * possibleMoves.length)
    const gameCopy = new Chess(currentGame.fen())
    const result = gameCopy.move(possibleMoves[randomIndex])

    setGame(gameCopy)
    setLastMove(result?.san)
  }

  function makeAMove(move: any) {
    const gameCopy = new Chess(game.fen())
    const result = gameCopy.move(move)

    if (!result) return null

    setGame(gameCopy)
    setLastMove(result.san)

    return { result, gameCopy }
  }

  function onDrop({
    sourceSquare,
    targetSquare
  }: {
    sourceSquare: string
    targetSquare: string | null
  }) {
    if (!targetSquare) return false

    const moveResult = makeAMove({
      from: sourceSquare,
      to: targetSquare,
      promotion: 'q'
    })

    if (!moveResult) return false

    setTimeout(() => {
      makeRandomMove(moveResult.gameCopy)
    }, 200)

    return true
  }

  function handleSubmit() {
    onMove(game.pgn(), game.fen(), lastMove)
  }

  return (
    <div style={{ maxWidth: 400, margin: '0 auto', marginBottom: 16 }}>
      <div style={{ width: 360, margin: '0 auto' }}>
        <Chessboard
          options={{
            position: game.fen(),
            onPieceDrop: onDrop
          }}
        />
      </div>

      <p
        className="dim"
        style={{ textAlign: 'center', fontSize: 13, marginTop: 12 }}
      >
        Play a move against the random engine, then submit the current position.
      </p>

      <div style={{ textAlign: 'center', marginTop: 12 }}>
        <button type="button" onClick={handleSubmit}>
          Submit Move
        </button>
      </div>
    </div>
  )
}