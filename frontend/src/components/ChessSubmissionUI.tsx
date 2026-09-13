import { useState } from 'react'
import { Chess } from 'chess.js'
import { Chessboard } from 'react-chessboard'

export function ChessSubmissionUI({ onMove }: { onMove: (pgn: string, fen?: string, move?: string) => void }) {
  const [game, setGame] = useState(new Chess())

  function makeRandomMove() {
    const possibleMoves = game.moves()
    if (game.isGameOver() || game.isDraw() || possibleMoves.length === 0) return
    const randomIndex = Math.floor(Math.random() * possibleMoves.length)
    makeAMove(possibleMoves[randomIndex])
  }

  function makeAMove(move: any) {
    const gameCopy = new Chess(game.fen())
    const result = gameCopy.move(move)
    setGame(gameCopy)
    onMove(gameCopy.pgn(), gameCopy.fen(), result?.san)
    return result
  }

  function onDrop({ sourceSquare, targetSquare }: { sourceSquare: string, targetSquare: string | null }) {
    if (!targetSquare) return false
    const move = makeAMove({
      from: sourceSquare,
      to: targetSquare,
      promotion: 'q'
    })

    if (move === null) return false
    setTimeout(makeRandomMove, 200)
    return true
  }

  return (
    <div style={{ maxWidth: 400, margin: '0 auto', marginBottom: 16 }}>
      <div style={{ width: 360, margin: '0 auto' }}>
        <Chessboard options={{ position: game.fen(), onPieceDrop: onDrop }} />
      </div>
      <p className="dim" style={{ textAlign: 'center', fontSize: 13, marginTop: 12 }}>
        Play a move against the random engine. PGN payload is generated automatically.
      </p>
    </div>
  )
}
